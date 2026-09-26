"""Frozen, sequential torque-ratio comparison. Prepare -> smoke -> run.

Run with .venv-falsify/bin/python. No network, repository mutation or retries.
The subprocess log and atomic status JSON survive closing the Codex turn.
"""
import argparse
import datetime as dt
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import time

EXPERIMENT = Path(__file__).resolve().parents[1]
REPO = EXPERIMENT.parents[1]
MATLAB = '/Applications/MATLAB_R2026a.app/bin/matlab'
PSY = str(REPO.parent/'FIM'/'.venv-psy-arch/bin/python')


def write_json(path, value):
    path = Path(path)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(value, indent=2, allow_nan=False)+'\n')
    tmp.replace(path)


def environment():
    env = dict(os.environ)
    for name in ['OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS', 'MKL_NUM_THREADS',
                 'VECLIB_MAXIMUM_THREADS', 'NUMEXPR_NUM_THREADS']:
        env[name] = '1'
    env['PYTHONUNBUFFERED'] = '1'
    return env


def quote(value):
    return "'"+str(value).replace("'", "''")+"'"


def matlab(expression):
    return [MATLAB, '-singleCompThread', '-batch',
            f"addpath({quote(EXPERIMENT)}); setup_fim; {expression}"]


def execute(command, log):
    print('EXEC', ' '.join(command), flush=True)
    with open(log, 'x') as output:
        proc = subprocess.Popen(command, cwd=REPO, env=environment(),
                                stdout=output, stderr=subprocess.STDOUT)
        write_json(Path(log).with_suffix('.process.json'), {'PID': proc.pid, 'Command': command})
        code = proc.wait()
    if code:
        raise RuntimeError(f'Child exited {code}; see {log}')


def source_files():
    return [REPO/'driver.py', REPO/'falsify.m'] + sorted(
        p for p in EXPERIMENT.rglob('*') if p.is_file()
        and p.suffix in {'.py','.m','.json','.patch','.txt'}
        and '__pycache__' not in p.parts and 'evidence' not in p.parts)


def freeze(campaign):
    hashes = {}
    for source in source_files():
        relative = str(source.relative_to(REPO))
        target = campaign/'code_snapshot'/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        hashes[relative] = hashlib.sha256(source.read_bytes()).hexdigest()
    for source in sorted((campaign/'plants').iterdir())+[campaign/'FInjLib.slx']:
        hashes['@campaign/'+str(source.relative_to(campaign))] = hashlib.sha256(source.read_bytes()).hexdigest()
    for source in sorted((campaign/'wrappers').glob('*.slx')):
        hashes['@campaign/'+str(source.relative_to(campaign))] = hashlib.sha256(source.read_bytes()).hexdigest()
    for name in ['protocol.json','fault_catalog.csv','baseline-inputs.csv','fixed-inputs.csv']:
        source=campaign/name
        if source.is_file():
            hashes['@campaign/'+name]=hashlib.sha256(source.read_bytes()).hexdigest()
    for source in [REPO/'.deps/fim/arch/models/FALS/transmission/Autotrans_shift.mdl',
                   REPO/'.deps/fim/model-data/sldemo_autotrans_data.mat']:
        hashes[str(source.relative_to(REPO))]=hashlib.sha256(source.read_bytes()).hexdigest()
    write_json(campaign/'source-hashes.json', hashes)


def check_frozen(campaign):
    for name, expected in json.loads((campaign/'source-hashes.json').read_text()).items():
        source = campaign/name[10:] if name.startswith('@campaign/') else REPO/name
        assert hashlib.sha256(source.read_bytes()).hexdigest() == expected, f'Changed source: {source}'


def validate_protocol(protocol):
    # These values are also encoded in the Simulink/RL bridges. Fail closed
    # instead of accepting an edited JSON that the implementation ignores.
    expected=dict(stop_time_seconds=30,control_step_seconds=5,control_points=6,
        throttle_range_percent=[60,100],brake=0,target_speed_mph=95,deadline_seconds=20,
        gear_values=[1,2,3,4],robustness_scale_mph=80,solver='ode5',fixed_step_seconds=.01,
        workers=1,cpu_threads=1)
    for key,value in expected.items():
        assert protocol[key]==value, f'Unsupported bridge setting: {key}'
    assert list(zip(protocol['cases'],protocol['deltas']))==[
        ('T01',.02),('T04',.03),('T05',.04),('T02',.05),('T03',.10)]
    assert protocol['algorithms']==['RAND','ACER','A3C','DDQN','PSY']
    assert len(set(protocol['seeds']))==100 and protocol['max_inputs']==1500
    assert protocol['learning']['acer_replay_capacity']==10000
    assert protocol['psy']['initial_lhs']==100


def prepare(campaign):
    import numpy as np
    from scipy.stats import qmc
    campaign.mkdir(parents=True, exist_ok=False)
    (campaign/'plants').mkdir()
    protocol = json.loads((EXPERIMENT/'config/torque_comparison.json').read_text())
    validate_protocol(protocol)
    protocol['PreparedUTC'] = dt.datetime.now(dt.timezone.utc).isoformat()
    protocol['GitBranch'] = subprocess.check_output(['git','branch','--show-current'],cwd=REPO,text=True).strip()
    protocol['BaseCommit'] = subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip()
    assert protocol['GitBranch'] == 'FIM'
    write_json(campaign/'protocol.json', protocol)
    corners = np.array(list(itertools.product([60.,100.],repeat=6)))
    lhs = 60+40*qmc.LatinHypercube(d=6, seed=610031).random(64)
    np.savetxt(campaign/'baseline-inputs.csv', np.vstack((corners,lhs)),delimiter=',',fmt='%.17g')
    execute(matlab(f'prepare_fim_torque_models({quote(campaign)});'), campaign/'prepare.log')
    print('PREPARED', campaign, flush=True)


def trial(campaign, case, algorithm, seed, budget, folder):
    folder.parent.mkdir(parents=True, exist_ok=True)
    if algorithm == 'PSY':
        command = [PSY,str(EXPERIMENT/'python/run_torque_psy.py'),str(campaign),case,
                   str(seed),str(budget),str(folder)]
    else:
        command = matlab('run_fim_torque_search('+','.join(map(quote,[campaign,case,algorithm]))+
                         f',{seed},{budget},{quote(folder)});')
    execute(command, folder.with_suffix('.log'))
    result = json.loads((folder/'result.json').read_text())
    assert result['Status']=='complete'
    return result


def smoke(campaign):
    assert not (campaign/'preflight.json').exists()
    freeze(campaign)
    execute(matlab(f'validate_fim_torque_baseline({quote(campaign)});'),campaign/'baseline.log')
    results = []
    for algorithm, budget in [('RAND',2),('A3C',2),('ACER',12),('DDQN',90),('PSY',102)]:
        check_frozen(campaign)
        result = trial(campaign,'B00',algorithm,720031,budget,campaign/'smoke'/algorithm)
        assert not result['Violated'] and result['Episodes']==budget
        if algorithm == 'ACER':
            assert result['Learning']['ACEROnlineUpdates']>0 and result['Learning']['ACERReplayUpdates']>0
        if algorithm in ['A3C','DDQN']:
            assert result['Learning']['OptimizerUpdates']>0
        if algorithm == 'PSY':
            assert result['AdaptiveEvaluations']==2 and result['GPFitCount']>=2
        results.append(result)
    # Every generated fault wrapper must match an independent plant replay.
    for case in json.loads((campaign/'protocol.json').read_text())['cases']:
        results.append(trial(campaign,case,'RAND',720032,2,campaign/'smoke'/case))
    check_frozen(campaign)
    write_json(campaign/'preflight.json',{'Status':'PASS','Results':results,
               'Scope':'Learning and replay checks only; excluded from formal trials'})


def planned_jobs(protocol):
    jobs = []
    rng = random.Random(protocol['order_seed'])
    for seed in protocol['seeds']:
        block = list(itertools.product(protocol['cases'],protocol['algorithms']))
        rng.shuffle(block)
        jobs.extend([(case,algorithm,seed) for case,algorithm in block])
    assert len(jobs)==len(set(jobs))
    return jobs


def run(campaign):
    assert json.loads((campaign/'preflight.json').read_text())['Status']=='PASS'
    protocol = json.loads((campaign/'protocol.json').read_text())
    validate_protocol(protocol)
    jobs=planned_jobs(protocol)
    # Resuming preserves completed trials but never silently retries partial trials.
    results = []
    for case, algorithm, seed in jobs:
        if (campaign/'STOP_AFTER_TRIAL').exists():
            write_json(campaign/'status.json',dict(Status='stopped',Completed=len(results),Total=len(jobs),
                       Reason='STOP_AFTER_TRIAL requested; completed trials retained'))
            return
        check_frozen(campaign)
        folder=campaign/'trials'/f'{case}_{algorithm}_{seed}'
        if (folder/'result.json').exists():
            result=json.loads((folder/'result.json').read_text())
        else:
            assert not folder.exists(), f'Partial trial requires review: {folder}'
            write_json(campaign/'status.json',{'Status':'running','PID':os.getpid(),
                       'Completed':len(results),'Total':len(jobs),'Current':[case,algorithm,seed],
                       'UpdatedUTC':dt.datetime.now(dt.timezone.utc).isoformat()})
            result=trial(campaign,case,algorithm,seed,protocol['max_inputs'],folder)
        results.append(result)
        write_json(campaign/'results.json',results)
    write_json(campaign/'status.json',{'Status':'complete','Completed':len(results),'Total':len(jobs),
               'UpdatedUTC':dt.datetime.now(dt.timezone.utc).isoformat()})


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['prepare','smoke','run'])
    parser.add_argument('campaign',type=Path)
    args=parser.parse_args(); campaign=args.campaign.resolve()
    try:
        {'prepare':prepare,'smoke':smoke,'run':run}[args.mode](campaign)
    except Exception as error:
        if campaign.is_dir():
            write_json(campaign/'status.json',{'Status':'error','Stage':args.mode,
                       'Error':str(error),'PID':os.getpid()})
        raise


if __name__=='__main__':
    main()
