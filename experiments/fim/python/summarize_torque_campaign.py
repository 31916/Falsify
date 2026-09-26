"""Export inspectable CSVs from completed trials; retain censored failures.

Incomplete trials are never classified as no-counterexample. This script does
not modify the search logs. Run again as more independent trials complete.
"""
import argparse
import csv
import json
from pathlib import Path
from run_torque_campaign import write_json


def csv_write(path, rows, fields):
    with path.open('w',newline='') as output:
        writer=csv.DictWriter(output,fieldnames=fields)
        writer.writeheader(); writer.writerows(rows)


def summarize(campaign):
    protocol=json.loads((campaign/'protocol.json').read_text())
    trials=[]
    for file in sorted((campaign/'trials').glob('*/result.json')):
        result=json.loads(file.read_text())
        assert result['Status']=='complete'
        history=[json.loads(line) for line in (file.parent/'candidates.jsonl').read_text().splitlines()]
        assert len(history)==result['Episodes']
        assert [h['Episode'] for h in history]==list(range(1,len(history)+1))
        assert result['Violated']==(result['Rho']<0)
        assert abs(min(h['Rho'] for h in history)-result['Rho'])<1e-9
        assert result['Violated'] or result['Episodes']==protocol['max_inputs']
        if result['Violated']:
            assert history[-1]['Rho']<0 and all(h['Rho']>=0 for h in history[:-1])
            verification=history[-1]['Verification']
            assert verification['ValidCounterexample'] and verification['NormalRho']>=0
            assert verification['ReplayError']<1e-5
        assert result['SearchSeconds']>0 and result['VerificationSeconds']>0
        rows=[]
        for h in history:
            assert len(h['Throttle'])==6 and all(60<=u<=100 for u in h['Throttle'])
            row={k:h[k] for k in ['Episode','Rho','RhoMPH','SearchSeconds','GearPass']}
            row.update({f'Throttle{5*i}':u for i,u in enumerate(h['Throttle'])})
            row['Verified']=bool(h['Verification'])
            row['NormalRho']=h['Verification'].get('NormalRho','')
            row['Phase']=h.get('Phase','online_action_selection')
            rows.append(row)
        csv_write(file.parent/'candidates.csv',rows,list(rows[0]))
        learning=result.get('Learning',{})
        trials.append(dict(Case=result['Case'],Algorithm=result['Algorithm'],Seed=result['Seed'],
            Found=int(result['Violated']),Inputs=result['Episodes'],Budget=result['Budget'],
            Censored=int(not result['Violated']),BestRho=result['Rho'],
            SearchSeconds=result['SearchSeconds'],VerificationSeconds=result['VerificationSeconds'],
            OptimizerUpdates=learning.get('OptimizerUpdates',''),
            ACEROnlineUpdates=learning.get('ACEROnlineUpdates',''),
            ACERReplayUpdates=learning.get('ACERReplayUpdates',''),
            GPFitCount=result.get('GPFitCount','')))
    if trials:
        csv_write(campaign/'trial-results.csv',trials,list(trials[0]))
    summary=[]
    for case in protocol['cases']:
        for algorithm in protocol['algorithms']:
            group=[r for r in trials if r['Case']==case and r['Algorithm']==algorithm]
            row=dict(Case=case,Algorithm=algorithm,Completed=len(group),Planned=len(protocol['seeds']),
                     Found=sum(r['Found'] for r in group),Censored=sum(r['Censored'] for r in group))
            for budget in protocol['checkpoints']:
                found=sum(r['Found'] and r['Inputs']<=budget for r in group)
                row[f'FoundBy{budget}']=found
                row[f'RateBy{budget}']=found/len(group) if group else ''
            summary.append(row)
    csv_write(campaign/'summary.csv',summary,list(summary[0]))
    planned=len(protocol['cases'])*len(protocol['algorithms'])*len(protocol['seeds'])
    receipt=dict(Status='PASS',Completed=len(trials),Planned=planned,
                 Interpretation='final' if len(trials)==planned else 'partial; unfinished trials are not failures',
                 Checks=['row count','budget','first-negative stop','normal replay pass',
                         'input bounds','positive timing','censored trials retained'])
    write_json(campaign/'summary-audit.json',receipt)
    print(json.dumps(receipt,indent=2))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('campaign',type=Path)
    summarize(parser.parse_args().campaign.resolve())
