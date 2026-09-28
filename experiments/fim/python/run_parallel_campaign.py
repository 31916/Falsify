"""Two fresh Linux campaigns, four isolated four-CPU workers per campaign.

prepare runs in each named branch checkout. launch starts a detached supervisor:
both preflights must pass before any formal worker starts. No implicit resume,
retry or old-result import. A child error stops the whole pair for review.
"""
import argparse
import datetime as dt
import fcntl
import itertools
import json
import os
from pathlib import Path
import platform
import random
import signal
import subprocess
import sys
import time

import run_torque_campaign as shared
from run_stuck_campaign import validate_protocol as validate_stuck

REPO, EXPERIMENT = shared.REPO, shared.EXPERIMENT
SCRIPT = Path(__file__).resolve()


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def read(path):
    return json.loads(Path(path).read_text())


def execution():
    return read(EXPERIMENT/'config/parallel_execution.json')


def validate(protocol):
    family = protocol['fault_family']
    assert family in ('torque', 'stuck')
    assert protocol['workers'] == protocol['cpu_threads'] == 4
    assert protocol['parallel_execution'] == execution()
    assert protocol['cpu_affinity'] == execution()['cpu_affinity'][family]
    legacy = dict(protocol, workers=1, cpu_threads=1)
    (validate_stuck if family == 'stuck' else shared.validate_protocol)(legacy)


def schedule(protocol):
    """Pair methods by case/seed and balance CPU class exactly, not by outcomes."""
    workers = [[] for _ in range(4)]
    rng = random.Random(protocol['order_seed'])
    for seed_index, seed in enumerate(protocol['seeds']):
        cases = list(enumerate(protocol['cases']))
        rng.shuffle(cases)
        for case_index, case in cases:
            methods = list(protocol['algorithms'])
            rng.shuffle(methods)
            worker = (seed_index + case_index) % 4
            workers[worker].extend((case, method, seed) for method in methods)
    return workers


def configure(campaign, label, cpus):
    assert platform.system() == 'Linux'
    assert set(cpus) <= os.sched_getaffinity(0)
    os.sched_setaffinity(0, cpus)
    assert os.sched_getaffinity(0) == set(cpus)
    root = campaign/'workers'/label
    for folder in ('work', 'prefs', 'tmp'):
        (root/folder).mkdir(parents=True, exist_ok=True)
    os.environ.update(FIM_CPU_THREADS='4', FIM_WORK_DIR=str(root/'work'),
                      MATLAB_PREFDIR=str(root/'prefs'), TMPDIR=str(root/'tmp'))
    os.environ.update(shared.environment())
    return root


def prepare(campaign, family):
    import numpy as np
    from scipy.stats import qmc
    assert platform.system() == 'Linux'
    branch = subprocess.check_output(['git','branch','--show-current'],cwd=REPO,text=True).strip()
    assert branch == {'torque':'FIMトルク','stuck':'FIMStuck'}[family]
    assert not subprocess.check_output(['git','status','--porcelain'],cwd=REPO,text=True).strip()
    assert Path(shared.MATLAB).is_file() and Path(shared.PSY).is_file()
    protocol = read(EXPERIMENT/f'config/{family}_comparison.json')
    plan = execution()
    all_cpus = sum((sum(v, []) for v in plan['cpu_affinity'].values()), [])
    assert sorted(all_cpus) == list(range(32))
    assert set(all_cpus) <= os.sched_getaffinity(0)
    topology = json.loads(subprocess.check_output(['lscpu','-J','-e=CPU,CORE,SOCKET,MAXMHZ'],text=True))
    rows = {int(row['cpu']): row for row in topology['cpus']}
    for cpus in sum(plan['cpu_affinity'].values(), []):
        assert rows[cpus[0]]['core'] == rows[cpus[1]]['core']
        assert len({rows[c]['core'] for c in cpus}) == 3
        assert float(rows[cpus[0]]['maxmhz']) >= 5700
        assert all(float(rows[c]['maxmhz']) == 4400 for c in cpus[2:])
    protocol.update(id=plan['id']+'_'+family.upper(),fault_family=family,workers=4,cpu_threads=4,
        parallel_execution=plan,cpu_affinity=plan['cpu_affinity'][family],
        PreparedUTC=now(),GitBranch=branch,Repository=str(REPO),
        BaseCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),
        hardware_caveat=plan['timing_caveat'])
    validate(protocol)
    campaign.mkdir(parents=True, exist_ok=False)
    (campaign/'plants').mkdir()
    shared.write_json(campaign/'protocol.json', protocol)
    configure(campaign, 'prepare', protocol['cpu_affinity'][0])
    runtime = dict(Host=platform.node(),Platform=platform.platform(),Python=sys.version,
        MATLAB=shared.MATLAB,PsyPython=shared.PSY,FalsifyPython=sys.executable,
        Workers=4,CPUThreads=4,Topology=topology,
        BootID=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
        FalsifyPackages=subprocess.check_output([sys.executable,'-m','pip','freeze'],text=True).splitlines(),
        PsyPackages=subprocess.check_output([shared.PSY,'-m','pip','freeze'],text=True).splitlines())
    shared.write_json(campaign/'runtime.json', runtime)
    corners = np.array(list(itertools.product([60.,100.], repeat=6)))
    lhs = 60+40*qmc.LatinHypercube(d=6, seed=610031).random(64)
    np.savetxt(campaign/'baseline-inputs.csv',np.vstack((corners,lhs)),delimiter=',',fmt='%.17g')
    expression = (f'prepare_fim_stuck({shared.quote(campaign)}); '
                  f'prepare_fim_torque_comparison({shared.quote(campaign)});' if family == 'stuck'
                  else f'prepare_fim_torque_models({shared.quote(campaign)});')
    shared.execute(shared.matlab(expression), campaign/'prepare.log')
    shared.freeze(campaign)
    shared.write_json(campaign/'status.json',dict(Status='prepared',Completed=0,
        Total=sum(map(len,schedule(protocol))),UpdatedUTC=now()))


def preflight(campaign):
    protocol = read(campaign/'protocol.json'); validate(protocol)
    shared.check_frozen(campaign)
    configure(campaign, 'preflight', protocol['cpu_affinity'][0])
    if protocol['fault_family'] == 'stuck':
        shared.execute(shared.matlab(f'test_fim_stuck_native({shared.quote(campaign)}); '
            f'validate_fim_stuck_replays({shared.quote(campaign)});'), campaign/'native-replays.log')
    shared.smoke(campaign)


def worker(campaign, index):
    protocol = read(campaign/'protocol.json'); validate(protocol)
    assert read(campaign/'preflight.json')['Status'] == 'PASS'
    jobs = schedule(protocol)[index]
    root = configure(campaign, str(index), protocol['cpu_affinity'][index])
    # A trial is isolated even from a previous method's disk cache/prefs.
    assert not (root/'status.json').exists(), 'No implicit restart or resume'
    completed = 0
    try:
        for case, algorithm, seed in jobs:
            if (campaign/'STOP_AFTER_TRIAL').exists():
                shared.write_json(root/'status.json',dict(Status='stopped',Completed=completed,Total=len(jobs)))
                return
            shared.check_frozen(campaign)
            folder = campaign/'trials'/f'{case}_{algorithm}_{seed}'
            assert not folder.exists() and not folder.with_suffix('.log').exists()
            workspace = root/'runtime'/folder.name
            for name in ('work','prefs','tmp'):
                (workspace/name).mkdir(parents=True, exist_ok=False)
            os.environ.update(FIM_WORK_DIR=str(workspace/'work'),
                              MATLAB_PREFDIR=str(workspace/'prefs'),TMPDIR=str(workspace/'tmp'))
            started = now(); clock = time.perf_counter()
            shared.write_json(root/'status.json',dict(Status='running',Completed=completed,Total=len(jobs),
                PID=os.getpid(),Current=[case,algorithm,seed],CPUs=sorted(os.sched_getaffinity(0)),UpdatedUTC=started))
            result = shared.trial(campaign,case,algorithm,seed,protocol['max_inputs'],folder)
            assert (result['Case'],result['Algorithm'],result['Seed']) == (case,algorithm,seed)
            assert result['Budget'] == protocol['max_inputs']
            shared.write_json(folder/'execution.json',dict(Worker=index,CPUs=sorted(os.sched_getaffinity(0)),
                CPUThreads=4,StartedUTC=started,CompletedUTC=now(),
                TotalProcessSeconds=time.perf_counter()-clock,Workspace=str(workspace)))
            completed += 1
        shared.write_json(root/'status.json',dict(Status='complete',Completed=completed,Total=len(jobs),UpdatedUTC=now()))
    except BaseException as error:
        shared.write_json(root/'status.json',dict(Status='error',Completed=completed,Total=len(jobs),Error=repr(error)))
        raise


def capacity(campaign, index):
    protocol = read(campaign/'protocol.json'); validate(protocol)
    shared.check_frozen(campaign)
    root = configure(campaign, 'capacity-'+str(index), protocol['cpu_affinity'][index])
    result = shared.trial(campaign,'B00','RAND',730031+index,2,campaign/'capacity'/str(index))
    assert not result['Violated'] and result['Episodes']==2
    shared.write_json(root/'check.json',dict(Status='PASS',CPUs=sorted(os.sched_getaffinity(0))))


def command(campaign, mode, *extra):
    protocol = read(campaign/'protocol.json'); runtime = read(campaign/'runtime.json')
    repo = Path(protocol['Repository'])
    env = shared.environment()
    env.update(FIM_MATLAB=runtime['MATLAB'],FIM_PSY_PYTHON=runtime['PsyPython'],FIM_CPU_THREADS='4')
    return [runtime['FalsifyPython'],str(repo/'experiments/fim/python/run_parallel_campaign.py'),
            mode,str(campaign),*map(str,extra)], repo, env


def spawn(campaign, mode, *extra):
    args, cwd, env = command(campaign, mode, *extra)
    log = campaign/(mode+('-'+str(extra[0]) if extra else '')+'.log')
    with log.open('x') as output:
        process = subprocess.Popen(args,cwd=cwd,env=env,stdout=output,stderr=subprocess.STDOUT,
                                   start_new_session=True)
    shared.write_json(log.with_suffix('.process.json'),dict(PID=process.pid,Command=args,Log=str(log)))
    return process


def stop_children(children):
    # Every child is our own new session. Never target unrelated MATLAB jobs.
    for child in children:
        try: os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError: pass
    deadline = time.monotonic()+10
    while time.monotonic()<deadline and any(p.poll() is None for p in children):
        time.sleep(.2)
    for child in children:
        try: os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError: pass


def supervise(campaigns):
    children = []
    def interrupted(signum, frame):
        raise RuntimeError(f'Supervisor interrupted by signal {signum}')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    lock_path = Path.home()/'research/fim-parallel-pair.lock'
    with lock_path.open('a') as lock:
        fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            for campaign in campaigns:
                assert not (campaign/'trials').exists(), 'Fresh campaigns only'
                shared.write_json(campaign/'status.json',dict(Status='preflight',Completed=0,UpdatedUTC=now()))
                children.append(spawn(campaign,'preflight'))
            while any(p.poll() is None for p in children):
                assert all(p.poll() in (None,0) for p in children), 'Preflight process failed'
                time.sleep(5)
            assert all(p.returncode == 0 for p in children), 'Preflight process failed'
            assert all(read(c/'preflight.json')['Status'] == 'PASS' for c in campaigns)
            children = []
            for c in campaigns:
                for i in range(4):
                    children.append(spawn(c,'capacity',i))
            for campaign in campaigns:
                shared.write_json(campaign/'status.json',dict(Status='capacity_check',Completed=0,UpdatedUTC=now()))
            while any(p.poll() is None for p in children):
                assert all(p.poll() in (None,0) for p in children), 'Eight-process capacity check failed'
                time.sleep(5)
            assert all(p.returncode == 0 for p in children), 'Eight-process capacity check failed'
            children = []
            for campaign in campaigns:
                for index in range(4):
                    children.append(spawn(campaign,'worker',index))
            shared.write_json(campaigns[0]/'formal-start.json',dict(StartedUTC=now(),PIDs=[p.pid for p in children]))
            while True:
                codes = [p.poll() for p in children]
                assert all(code in (None,0) for code in codes), 'Formal worker failed; both campaigns halted'
                for campaign in campaigns:
                    states = [read(campaign/'workers'/str(i)/'status.json')
                              for i in range(4) if (campaign/'workers'/str(i)/'status.json').exists()]
                    complete = len(states)==4 and all(s['Status']=='complete' for s in states)
                    protocol = read(campaign/'protocol.json')
                    shared.write_json(campaign/'status.json',dict(Status='complete' if complete else 'running',
                        Completed=sum(s['Completed'] for s in states),
                        Total=len(protocol['cases'])*len(protocol['seeds'])*len(protocol['algorithms']),
                        Workers=states,UpdatedUTC=now()))
                if all(code == 0 for code in codes):
                    break
                with (campaigns[0]/'server-resources.jsonl').open('a') as output:
                    output.write(json.dumps(dict(UTC=now(),Load=os.getloadavg(),
                        Memory=Path('/proc/meminfo').read_text(),ActiveWorkers=sum(c is None for c in codes)))+'\n')
                time.sleep(10)
            assert all(read(c/'status.json')['Status']=='complete' for c in campaigns), 'Workers stopped before completion'
            for campaign in campaigns:
                _, repo, env = command(campaign,'preflight')
                runtime = read(campaign/'runtime.json')
                subprocess.run([runtime['FalsifyPython'],str(repo/'experiments/fim/python/summarize_torque_campaign.py'),
                    str(campaign)],cwd=repo,env=env,check=True)
        except BaseException as error:
            stop_children(children)
            for campaign in campaigns:
                state = read(campaign/'status.json')
                state.update(Status='error',Error=repr(error),UpdatedUTC=now())
                shared.write_json(campaign/'status.json',state)
            raise


def launch(campaigns):
    assert len(campaigns)==2 and len(set(campaigns))==2
    protocols = [read(c/'protocol.json') for c in campaigns]
    assert [p['fault_family'] for p in protocols] == ['torque','stuck']
    assert protocols[0]['BaseCommit'] == protocols[1]['BaseCommit']
    assert sorted(sum((sum(p['cpu_affinity'],[]) for p in protocols),[])) == list(range(32))
    for c in campaigns:
        assert not (c/'launch.json').exists() and not (c/'preflight.json').exists()
        assert read(c/'status.json')['Status']=='prepared'
    with (campaigns[0]/'supervisor.log').open('x') as output:
        process = subprocess.Popen([sys.executable,str(SCRIPT),'supervise',*map(str,campaigns)],
            cwd=REPO,env=shared.environment(),stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
    receipt = dict(PID=process.pid,Campaigns=list(map(str,campaigns)),StartedUTC=now(),
                   Stage='two preflights, then eight formal workers only after both PASS')
    for c in campaigns: shared.write_json(c/'launch.json',receipt)
    print(json.dumps(receipt,indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['prepare','preflight','capacity','worker','launch','supervise'])
    parser.add_argument('campaign',type=Path)
    parser.add_argument('extra',nargs='?')
    args = parser.parse_args(); campaign = args.campaign.resolve()
    if args.mode == 'prepare': prepare(campaign,args.extra)
    elif args.mode == 'preflight': preflight(campaign)
    elif args.mode == 'worker': worker(campaign,int(args.extra))
    elif args.mode == 'capacity': capacity(campaign,int(args.extra))
    else: globals()[args.mode]([campaign,Path(args.extra).resolve()])


if __name__ == '__main__': main()
