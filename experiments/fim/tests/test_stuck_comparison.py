"""Protocol and scheduling checks without MATLAB or remote side effects."""
import copy
import json
from pathlib import Path
import sys
import unittest

REPO=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(REPO/'experiments/fim/python'))
from run_stuck_campaign import validate_protocol
from run_torque_campaign import planned_jobs


class StuckProtocolTest(unittest.TestCase):
    def setUp(self):
        self.protocol=json.loads((REPO/'experiments/fim/config/stuck_comparison.json').read_text())

    def test_all_prespecified_trials(self):
        validate_protocol(self.protocol)
        jobs=planned_jobs(self.protocol)
        self.assertEqual(len(jobs),4500)
        self.assertEqual(jobs,planned_jobs(self.protocol))
        for case in self.protocol['cases']:
            for method in self.protocol['algorithms']:
                self.assertEqual(len([j for j in jobs if j[:2]==(case,method)]),100)
        for i,seed in enumerate(self.protocol['seeds']):
            self.assertEqual({j[2] for j in jobs[i*45:(i+1)*45]},{seed})

    def test_reject_silent_condition_changes(self):
        for key,value in [('durations_seconds',[1,2,3]),('max_inputs',10),
                          ('gear_values',[1,4]),('workers',2),('deadline_seconds',30),
                          ('seeds',[490001]*100),('fault_source','TorqueRatio')]:
            protocol=copy.deepcopy(self.protocol); protocol[key]=value
            with self.assertRaises(AssertionError,msg=key): validate_protocol(protocol)
        protocol=copy.deepcopy(self.protocol); protocol['learning']['acer_replay_capacity']=10
        with self.assertRaises(AssertionError): validate_protocol(protocol)


if __name__=='__main__': unittest.main()
