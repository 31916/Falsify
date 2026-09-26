"""Independent monitor boundary tests (no MATLAB needed)."""
import sys
import subprocess
from pathlib import Path
import unittest

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from monitor_metrics import metrics


class TorqueTests(unittest.TestCase):
    def setUp(self):
        self.data = np.zeros(3001, dtype=[("TimeSeconds", float), ("SpeedMPH", float), ("Gear", float)])
        self.data["TimeSeconds"] = np.arange(3001) / 100
        self.data["SpeedMPH"] = 50
        self.data["Gear"] = 1

    def test_inclusive_boundaries(self):
        for gear in (1, 4):
            self.data["Gear"] = gear
            m = metrics(self.data, 20, 50)
            self.assertTrue(m["GearRangePass"] and m["GearDiscretePass"] and m["AccelerationPass"])
            self.assertEqual(m["GearRho"], 0)

    def test_outside_and_noninteger_gears(self):
        for gear in (0.999999, 4.000001, 0, 5):
            self.data["Gear"] = gear
            self.assertFalse(metrics(self.data, 20, 50)["GearRangePass"])
        self.data["Gear"] = 2.5
        m = metrics(self.data, 20, 50)
        self.assertTrue(m["GearRangePass"])
        self.assertFalse(m["GearDiscretePass"])

    def test_closed_deadline(self):
        self.data["SpeedMPH"] = 49
        self.data["SpeedMPH"][2000] = 50
        self.assertTrue(metrics(self.data, 20, 50)["AccelerationPass"])
        self.data["SpeedMPH"][2000] = 49
        self.data["SpeedMPH"][2001] = 50
        self.assertFalse(metrics(self.data, 20, 50)["AccelerationPass"])

    def test_missing_arrival_is_not_zero(self):
        self.data["SpeedMPH"] = 49
        self.assertTrue(np.isnan(metrics(self.data, 20, 50)["FirstReachSeconds"]))

    def test_mask_patch_applies_to_pinned_dependency(self):
        root = Path(__file__).resolve().parents[1]
        dependency = root.parents[1] / ".deps/fim/fimtool-r2026a"
        if not dependency.exists():
            self.skipTest("FIM dependency not installed")
        patch = root / "dependencies/fim-masked-subsystems.patch"
        completed = subprocess.run(
            ["patch", "--dry-run", "--batch", "--forward", "-p1", "-d", str(dependency)],
            input=patch.read_text(), text=True, capture_output=True)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
