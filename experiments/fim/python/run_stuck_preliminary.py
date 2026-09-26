"""Reproducible native Stuck-at fixed-input screen, separate from tool ranking."""
import argparse
import csv
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import subprocess

from fixed_input_design import fixed_inputs
from run_torque_campaign import (EXPERIMENT, REPO, write_json, quote, matlab,
                                 execute, freeze, check_frozen)
from summarize_torque_campaign import csv_write


def prepare(campaign):
    campaign.mkdir(parents=True,exist_ok=False)
    (campaign/'plants').mkdir()
    protocol=json.loads((EXPERIMENT/'config/stuck_preliminary.json').read_text())
    protocol.update(PreparedUTC=dt.datetime.now(dt.timezone.utc).isoformat(),
        BaseCommit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip())
    write_json(campaign/'protocol.json',protocol)
    rows=fixed_inputs(); csv_write(campaign/'fixed-inputs.csv',rows,list(rows[0]))
    execute(matlab(f'prepare_fim_stuck({quote(campaign)});'),campaign/'prepare.log')
    execute(matlab(f'test_fim_stuck_native({quote(campaign)});'),campaign/'native-block-checks.log')


def read_csv(path):
    with path.open() as handle:
        return list(csv.DictReader(handle))


def audit(campaign):
    import numpy as np
    rows=read_csv(campaign/'fixed/results.csv')
    catalog=read_csv(campaign/'fault_catalog.csv')
    inputs=read_csv(campaign/'fixed-inputs.csv')
    expected={(c['ID'],i['InputID']) for c in catalog for i in inputs}
    assert len(rows)==len(expected)==1300
    assert {(r['Case'],r['InputID']) for r in rows}==expected
    checks=read_csv(campaign/'fixed/checks.csv')
    lookup={(r['Case'],r['InputID']):r for r in checks}
    assert len(lookup)==len(checks)
    for case in catalog[1:]:
        for inp in inputs[:6]:
            assert (case['ID'],inp['InputID']) in lookup
    for row in rows:
        data=np.genfromtxt(campaign/'fixed/traces'/f"{row['Case']}_{row['InputID']}.csv",delimiter=',',names=True)
        assert len(data)==3001 and all(np.isfinite(data[n]).all() for n in data.dtype.names)
        t=data['TimeSeconds']; np.testing.assert_allclose(t,np.arange(3001)/100,atol=1e-10,rtol=0)
        for name in ['Gear','CommandedGear','AppliedGear']:
            assert np.isin(data[name],[1,2,3,4]).all()
        onset,duration=float(row['Onset']),float(row['Duration'])
        active=(t>=onset-1e-10)&(t<onset+duration-1e-10)
        expected=data['CommandedGear'].copy()
        if row['Case']!='B00':
            expected[active]=expected[np.flatnonzero(t<onset-1e-10)[-1]]
        np.testing.assert_array_equal(data['AppliedGear'],expected)
        np.testing.assert_array_equal(data['FaultGate'],active.astype(float))
        ratios=np.array([2.393,1.45,1.,.677])[data['AppliedGear'].astype(int)-1]
        np.testing.assert_allclose(data['GearRatio'],ratios,atol=1e-10,rtol=0)
        margin=data['SpeedMPH'][t<=20+1e-10].max()-95
        assert abs(margin-float(row['MarginMPH']))<1e-8
        assert int(row['Violation'])==int(margin<0) and float(row['NormalMarginMPH'])>=0
        assert int(row['HeldSamples'])==np.count_nonzero(data['CommandedGear']!=data['AppliedGear'])
        if margin<0:
            assert float(lookup[row['Case'],row['InputID']]['CounterexampleReplayError'])<1e-7
    assert all(float(r['DisabledReplayError'])<1e-7 for r in checks)
    native=read_csv(campaign/'native-block-checks.csv')
    assert len(native)==18 and all(float(r['MaximumError'])==0 for r in native)
    summary=[]
    for case in catalog:
        group=[r for r in rows if r['Case']==case['ID']]
        failed=[r for r in group if int(r['Violation'])]
        summary.append(dict(Case=case['ID'],Onset=case['Onset'],Duration=case['Duration'],
            Inputs=len(group),InputsWithHeldShift=sum(int(r['HeldSamples'])>0 for r in group),
            Violations=len(failed),MinMarginMPH=min(float(r['MarginMPH']) for r in group),
            ViolatingInputs=';'.join(r['InputID'] for r in failed)))
    csv_write(campaign/'summary.csv',summary,list(summary[0]))
    write_json(campaign/'audit.json',dict(Status='PASS',Waveforms=len(rows),NativeBlockTests=18,
        DisabledChecks=len(checks),CounterexampleReplays=sum(int(r['Violation']) for r in rows),
        Scope='Finite paired-input screen, not tool performance or proof for all inputs'))
    print(json.dumps(summary,indent=2))


def run(campaign):
    with (REPO/'results/fim/experiment-worker.lock').open('a') as lock:
        fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        freeze(campaign)
        awake=subprocess.Popen(['/usr/bin/caffeinate','-i','-w',str(os.getpid())])
        try:
            write_json(campaign/'status.json',dict(Status='running',PID=os.getpid(),Stage='fixed screen'))
            execute(matlab(f'run_fim_stuck_pilot({quote(campaign)});'),campaign/'fixed.log')
            check_frozen(campaign); audit(campaign)
            write_json(campaign/'status.json',dict(Status='complete',Comparisons=1300))
        except Exception as error:
            write_json(campaign/'status.json',dict(Status='error',Error=str(error)))
            raise
        finally:
            awake.terminate()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['prepare','run','audit'])
    parser.add_argument('campaign',type=Path)
    args=parser.parse_args()
    {'prepare':prepare,'run':run,'audit':audit}[args.mode](args.campaign.resolve())


if __name__=='__main__':
    main()
