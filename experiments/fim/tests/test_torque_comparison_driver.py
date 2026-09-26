"""Exercise real Falsify factories without Simulink; not performance results."""
import json
from pathlib import Path
import sys
import unittest
import numpy as np

REPO=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(REPO))
sys.path.insert(0,str(REPO/'experiments/fim/python'))
import fim_comparison_driver as bridge


class TorqueDriverTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bridge.install(10000)

    def test_learning_and_alignment(self):
        results={}
        for algorithm, count in [('RAND',2),('A3C',2),('ACER',12),('DDQN',90)]:
            np.random.seed(720099)
            bridge.start_learning(algorithm,3,1,0)
            for episode in range(count):
                for t in range(0,30,5):
                    action=bridge.action(np.array([-.5,0,0]),t)
                    self.assertTrue(-1<=action[0]<=1)
                self.assertEqual(len(json.loads(bridge.episode_json())),6)
                with self.assertRaises(AssertionError):
                    bridge.action(np.zeros(3),30)
                bridge.finish_episode(np.zeros(3),-.1)
            stats=json.loads(bridge.stats_json())
            self.assertEqual(stats['Transitions'],count*6)
            self.assertEqual(stats['CompletedEpisodes'],count)
            self.assertEqual(stats['CurrentActions'],0)
            results[algorithm]=stats
        self.assertEqual(results['RAND']['OptimizerUpdates'],0)
        self.assertEqual(results['A3C']['OptimizerUpdates'],4)
        self.assertEqual(results['ACER']['ACEROnlineUpdates'],24)
        self.assertGreater(results['ACER']['ACERReplayUpdates'],0)
        self.assertGreater(results['DDQN']['OptimizerUpdates'],0)
        print(json.dumps(results,indent=2))


if __name__=='__main__':
    unittest.main()
