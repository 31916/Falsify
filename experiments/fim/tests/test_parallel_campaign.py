"""Scheduling/CPU/failure guards; no SSH, simulations, or process termination."""
import copy
import json
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'python'))
import run_parallel_campaign as parallel
import run_torque_campaign as shared


def protocol(family):
    p = json.loads((ROOT/f'config/{family}_comparison.json').read_text())
    p.update(fault_family=family,workers=4,cpu_threads=4,
             parallel_execution=parallel.execution(),cpu_affinity=parallel.execution()['cpu_affinity'][family])
    return p


class ParallelTest(unittest.TestCase):
    def test_cpu_partition(self):
        groups = sum(parallel.execution()['cpu_affinity'].values(),[])
        self.assertEqual(len(groups),8)
        self.assertTrue(all(len(g)==4 for g in groups))
        self.assertEqual(sorted(sum(groups,[])),list(range(32)))

    def test_unique_balanced_paired_trials(self):
        for family,total in [('torque',2500),('stuck',4500)]:
            p = protocol(family); parallel.validate(p)
            workers = parallel.schedule(p)
            self.assertEqual(workers,parallel.schedule(p))
            self.assertEqual(len(set(sum(workers,[]))),total)
            for jobs in workers:
                self.assertEqual(len(jobs),total//4)
                for case in p['cases']:
                    for method in p['algorithms']:
                        self.assertEqual(sum(c==case and m==method for c,m,s in jobs),25)
                for offset in range(0,len(jobs),5):
                    block = jobs[offset:offset+5]
                    self.assertEqual(len({(c,s) for c,m,s in block}),1)
                    self.assertEqual({m for c,m,s in block},set(p['algorithms']))

    def test_reject_changed_conditions(self):
        for family in ['torque','stuck']:
            for key,value in [('cpu_threads',8),('workers',8),('max_inputs',10),
                              ('cpu_affinity',[[0,1,2,3]]*4),('deadline_seconds',30)]:
                p=copy.deepcopy(protocol(family)); p[key]=value
                with self.assertRaises(AssertionError,msg=key): parallel.validate(p)

    def test_thread_limits_and_legacy_default(self):
        with patch.dict(os.environ,{'FIM_CPU_THREADS':'4'}):
            self.assertNotIn('-singleCompThread',shared.matlab('disp(1);'))
            self.assertEqual(shared.environment()['OPENBLAS_NUM_THREADS'],'4')
        with patch.dict(os.environ,{'FIM_CPU_THREADS':'1'}):
            self.assertIn('-singleCompThread',shared.matlab('disp(1);'))
        with patch.dict(os.environ,{'FIM_CPU_THREADS':'32'}):
            with self.assertRaises(AssertionError): shared.environment()


if __name__=='__main__': unittest.main()
