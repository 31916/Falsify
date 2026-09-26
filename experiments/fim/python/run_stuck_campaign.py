"""Frozen Linux Stuck-at comparison; preflight must pass before formal trials.

Set FIM_MATLAB and FIM_PSY_PYTHON to the dedicated installation. No changes to
fault timing, input domain or requirements are permitted after preparation.
"""
import argparse
import datetime as dt
import fcntl
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import subprocess
import sys

import run_torque_campaign as shared
from summarize_torque_campaign import summarize

REPO, EXPERIMENT = shared.REPO, shared.EXPERIMENT


def validate_protocol(protocol):
    expected = dict(fault_family='stuck',fault_type='Stuck-at',
        fault_level='Transmission/TransmissionRatio',fault_source='gear',
        onsets_seconds=[5,10,15],durations_seconds=[.2,.5,1.0],
        cases=[f'S{i:02d}' for i in range(1,10)],
        stop_time_seconds=30,control_step_seconds=5,control_points=6,
        throttle_range_percent=[60,100],brake=0,target_speed_mph=95,deadline_seconds=20,
        gear_values=[1,2,3,4],robustness_scale_mph=80,solver='ode5',fixed_step_seconds=.01,
        workers=1,cpu_threads=1,algorithms=['RAND','ACER','A3C','DDQN','PSY'],max_inputs=1500,
        seeds=list(range(490001,490101)),checkpoints=[100,500,1500])
    for key,value in expected.items():
        assert protocol[key]==value, f'Unsupported Stuck-at setting: {key}'
    learning=dict(intermediate_reward=0,terminal_reward='exp(-normalized_acceleration_robustness)-1',
        terminal_done=True,actions_per_episode=6,acer_replay_capacity=10000,
        acer_replay_start_size=50,acer_t_max=5,a3c_t_max=5,ddqn_replay_start_size=500,
        ddqn_update_interval=1,ddqn_target_update_interval=100)
    assert protocol['learning']==learning
    assert protocol['psy']==dict(initial_lhs=100,requirements=1,method='falsification',dimension=6)
    assert protocol['baseline_validation']==dict(corner_inputs=64,lhs_inputs=64,seed=610031)


def prepare(campaign):
    import numpy as np
    from scipy.stats import qmc
    assert platform.system()=='Linux', 'Run this experiment on the selected Linux server.'
    for name in ['FIM_MATLAB','FIM_PSY_PYTHON']:
        assert os.environ.get(name) and Path(os.environ[name]).is_file(), f'Set {name}'
    branch=subprocess.check_output(['git','branch','--show-current'],cwd=REPO,text=True).strip()
    assert branch=='FIMStuck'
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=REPO,text=True).strip(), 'Commit before freezing.'
    protocol=json.loads((EXPERIMENT/'config/stuck_comparison.json').read_text())
    validate_protocol(protocol)
    campaign.mkdir(parents=True,exist_ok=False); (campaign/'plants').mkdir()
    protocol.update(PreparedUTC=dt.datetime.now(dt.timezone.utc).isoformat(),GitBranch=branch,
        BaseCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip())
    shared.write_json(campaign/'protocol.json',protocol)
    runtime=dict(Host=platform.node(),Platform=platform.platform(),Machine=platform.machine(),
        Python=sys.version,MATLAB=shared.MATLAB,PsyPython=shared.PSY,Workers=1,CPUThreads=1,
        FalsifyPackages=subprocess.check_output([sys.executable,'-m','pip','freeze'],text=True).splitlines(),
        PsyPackages=subprocess.check_output([shared.PSY,'-m','pip','freeze'],text=True).splitlines())
    shared.write_json(campaign/'runtime.json',runtime)
    corners=np.array(list(itertools.product([60.,100.],repeat=6)))
    lhs=60+40*qmc.LatinHypercube(d=6,seed=610031).random(64)
    np.savetxt(campaign/'baseline-inputs.csv',np.vstack((corners,lhs)),delimiter=',',fmt='%.17g')
    shared.execute(shared.matlab(f'prepare_fim_stuck({shared.quote(campaign)}); '
        f'prepare_fim_torque_comparison({shared.quote(campaign)});'),campaign/'prepare.log')
    shared.freeze(campaign)
    shared.write_json(campaign/'status.json',dict(Status='prepared',Total=4500,Completed=0))


def smoke(campaign):
    shared.check_frozen(campaign)
    validate_protocol(json.loads((campaign/'protocol.json').read_text()))
    shared.write_json(campaign/'status.json',dict(Status='preflight',Completed=0,Total=4500,
        Stage='native hold/release, paired replay, baseline and learning checks'))
    shared.execute(shared.matlab(f'test_fim_stuck_native({shared.quote(campaign)}); '
        f'validate_fim_stuck_replays({shared.quote(campaign)});'),campaign/'native-replays.log')
    # Shared preflight: 128 normal inputs; A3C/ACER/DDQN updates; 100 LHS +
    # 2 adaptive PSY inputs; every fault wrapper replayed against native plant.
    shared.smoke(campaign)


def run(campaign):
    shared.run(campaign,validator=validate_protocol)
    summarize(campaign)


def launch(campaign):
    shared.check_frozen(campaign)
    assert not (campaign/'launch.json').exists(), 'Already launched; inspect its worker before resuming.'
    with (campaign/'campaign.log').open('x') as log:
        process=subprocess.Popen([sys.executable,str(Path(__file__).resolve()),'worker',str(campaign)],
            cwd=REPO,env=shared.environment(),stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
    receipt=dict(PID=process.pid,Campaign=str(campaign),Log=str(campaign/'campaign.log'),
        Stage='preflight then formal trials only on PASS',
        LauncherSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    shared.write_json(campaign/'launch.json',receipt)
    print(json.dumps(receipt,indent=2))


def worker(campaign):
    # Lock survives SSH disconnection; no Mac-specific sleep utility on Linux.
    with (REPO/'results/fim/experiment-worker.lock').open('a') as lock:
        fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        shared.check_frozen(campaign)
        if not (campaign/'preflight.json').exists():
            smoke(campaign)
        run(campaign)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['prepare','smoke','run','launch','worker'])
    parser.add_argument('campaign',type=Path)
    args=parser.parse_args(); campaign=args.campaign.resolve()
    try:
        globals()[args.mode](campaign)
    except Exception as error:
        if campaign.is_dir():
            shared.write_json(campaign/'status.json',dict(Status='error',Stage=args.mode,
                Error=str(error),PID=os.getpid()))
        raise


if __name__=='__main__':
    main()
