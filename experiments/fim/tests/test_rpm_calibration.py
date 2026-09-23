"""Boundary, activation-time and recommendation-unit tests; no MATLAB needed."""
import sys
from pathlib import Path
import unittest
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'python'))
from audit_rpm_calibration import critical_offset, robustness, choose_offset


class CalibrationTests(unittest.TestCase):
    def test_only_post_activation_peak_controls_boundary(self):
        y = np.array([[5900,0,1],[4800,0,1],[4000,0,1]], dtype=float)
        self.assertEqual(critical_offset([0,5,30],y),1201)

    def test_boundary_is_not_negative(self):
        y = np.array([[1000,0,1],[6001,0,1]],dtype=float)
        self.assertEqual(robustness(y),0)
        y[-1,0]+=1
        self.assertAlmostEqual(robustness(y),-1/3000)
        y[-1,0]-=2
        self.assertAlmostEqual(robustness(y),1/3000)

    def test_recommendation_has_clearance_and_five_rpm_grid(self):
        cfg=dict(offset_min=500,recommendation_clearance_rpm=1,recommendation_step_rpm=5)
        self.assertEqual(choose_offset([1232.722812,1240.395218],cfg),1235)
        self.assertEqual(choose_offset([1234.9],cfg),1240)


if __name__ == '__main__':
    unittest.main()
