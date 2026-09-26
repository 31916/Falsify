"""Pilot design and result denominators, without starting any simulation."""
import csv
import itertools
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from fixed_input_design import fixed_inputs
from run_torque_campaign import planned_jobs, validate_protocol, EXPERIMENT
from summarize_torque_campaign import summarize


class PreliminaryTests(unittest.TestCase):
    def test_formal_design(self):
        protocol=json.loads((EXPERIMENT/'config/torque_comparison.json').read_text())
        validate_protocol(protocol)
        self.assertEqual(protocol['deltas'],[.02,.03,.04,.05,.10])
        self.assertEqual(len(protocol['seeds']),100)
        self.assertEqual(protocol['max_inputs'],1500)
        jobs=planned_jobs(protocol)
        self.assertEqual(jobs,planned_jobs(protocol))
        self.assertEqual(len(set(jobs)),2500)
        protocol['control_step_seconds']=10
        with self.assertRaises(AssertionError):
            validate_protocol(protocol)

    def test_fixed_inputs_are_unique_complete_and_deterministic(self):
        rows=fixed_inputs()
        self.assertEqual(rows,fixed_inputs())
        self.assertEqual(len(rows),130)
        vectors={tuple(r[f'Throttle{5*i}'] for i in range(6)) for r in rows}
        self.assertEqual(len(vectors),130)
        self.assertTrue(set(itertools.product([60.,100.],repeat=6)) <= vectors)
        self.assertTrue(all(60<=v<=100 for row in vectors for v in row))
        self.assertEqual(sum(r['Source']=='lhs' for r in rows),64)
        self.assertEqual([r['Source'] for r in rows[:6]],['representative']*6)

    def test_summary_uses_protocol_denominators(self):
        with tempfile.TemporaryDirectory() as directory:
            campaign=Path(directory)
            (campaign/'trials').mkdir()
            (campaign/'protocol.json').write_text(json.dumps(dict(
                cases=['T01','T04','T05'],algorithms=['RAND','ACER','A3C','DDQN','PSY'],
                seeds=[27101,27102,27103],max_inputs=200,checkpoints=[100,200])))
            summarize(campaign)
            receipt=json.loads((campaign/'summary-audit.json').read_text())
            self.assertEqual(receipt['Planned'],45)
            self.assertEqual(receipt['Completed'],0)
            with (campaign/'summary.csv').open() as f:
                rows=list(csv.DictReader(f))
            self.assertEqual(len(rows),15)
            self.assertTrue(all(r['Planned']=='3' and r['Completed']=='0' for r in rows))
            self.assertTrue(all(r['RateBy200']=='' for r in rows))


if __name__=='__main__':
    unittest.main()
