"""Independent CSV audit of the torque-ratio pilot (no MATLAB or tool search).

Usage: python audit_torque_acceleration.py RUN_DIRECTORY [--output audit.json]
CSV time is seconds, speed is mph, ratio is dimensionless. Missing arrival
times are NaN (not zero); finite traces and completed horizons are mandatory.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.io import loadmat


def read_rows(path):
    with Path(path).open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def read_trace(path):
    data = np.genfromtxt(path, delimiter=",", names=True, encoding="utf-8-sig")
    assert data.shape == (3001,), path
    for name in data.dtype.names:
        assert np.isfinite(data[name]).all(), (path, name)
    np.testing.assert_allclose(data["TimeSeconds"], np.arange(3001) / 100, rtol=0, atol=1e-10)
    return data


def metrics(data, deadline, target):
    speed, gear = data["SpeedMPH"], data["Gear"]
    in_window = data["TimeSeconds"] <= deadline + 1e-10
    rho = float(speed[in_window].max() - target)
    reach = np.flatnonzero(speed >= target)
    return {
        "AccelerationRhoMPH": rho,
        "AccelerationPass": rho >= 0,
        "GearRangePass": bool(((gear >= 1) & (gear <= 4)).all()),
        "GearDiscretePass": bool(np.isin(gear, [1, 2, 3, 4]).all()),
        "GearRho": float(min((gear - 1).min(), (4 - gear).min())),
        "FirstReachSeconds": float(data["TimeSeconds"][reach[0]]) if len(reach) else float("nan"),
        "SpeedAtDeadlineMPH": float(speed[in_window][-1]),
        "SpeedAt30MPH": float(speed[-1]),
    }


def audit(root):
    root = Path(root)
    manifest = json.loads((root / "manifest.json").read_text())
    spec = manifest["Spec"]
    target = json.loads((root / "target.json").read_text())
    rows = read_rows(root / "summary.csv")
    inputs = read_rows(root / "inputs.csv")
    assert len(rows) == 24 and len(inputs) == 42
    assert spec["GearRange"] == [1, 4] and spec["GearValues"] == [1, 2, 3, 4]
    assert spec["Deltas"] == [0.02, 0.05, 0.1] and spec["FaultTime"] == 5
    assert spec["Solver"] == "ode5" and spec["FixedStep"] == 0.01
    assert target["DeadlineSeconds"] == spec["AccelerationDeadline"] == 20
    expected = {(case, inp) for case in spec["CaseIDs"] for inp in spec["InputIDs"]}
    assert {(r["Case"], r["Input"]) for r in rows} == expected
    traces = {(c, i): read_trace(root / "traces" / f"{c}_{i}.csv") for c, i in expected}
    baseline_peaks = [traces["B00", i]["SpeedMPH"][:2001].max() for i in spec["InputIDs"]]
    expected_target = np.floor((min(baseline_peaks) - spec["BaselineClearanceMPH"]) /
                               spec["TargetRoundingMPH"]) * spec["TargetRoundingMPH"]
    assert abs(expected_target - target["TargetSpeedMPH"]) < 1e-10
    np.testing.assert_allclose(target["NormalPeaksMPH"], baseline_peaks, rtol=0, atol=1e-10)
    counts = {case: 0 for case in spec["CaseIDs"]}
    max_injection_error = max_product_error = max_off_error = 0.0
    results = []
    for row in rows:
        case, inp = row["Case"], row["Input"]
        data, base = traces[case, inp], traces["B00", inp]
        delta = float(row["Delta"])
        expected_delta = 0 if case == "B00" else spec["Deltas"][spec["CaseIDs"].index(case) - 1]
        assert delta == expected_delta
        selected = [r for r in inputs if r["Input"] == inp]
        declared = np.array([[float(r[k]) for k in ("TimeSeconds", "ThrottlePercent", "Brake")]
                             for r in selected])
        np.testing.assert_array_equal(declared[:, 0], np.arange(0, 31, 5))
        idx = spec["InputIDs"].index(inp)
        np.testing.assert_array_equal(declared[:, 1], spec["Throttle"][idx] + [spec["Throttle"][idx][-1]])
        assert (declared[:, 2] == 0).all()
        ticks = np.minimum(np.floor((data["TimeSeconds"] + 1e-10) / 5).astype(int), 6)
        np.testing.assert_allclose(data["ThrottlePercent"], declared[ticks, 1], rtol=0, atol=1e-10)
        assert (data["Brake"] == 0).all()
        active = data["TimeSeconds"] >= 5 - 1e-10
        inj = np.max(np.abs(data["TorqueRatioAfter"] - (data["TorqueRatioBefore"] - delta * active)))
        product = np.max(np.abs(data["TurbineTorque"] - data["ImpellerTorque"] * data["TorqueRatioAfter"]))
        assert inj < 1e-10 and product < 1e-7
        assert (data["TorqueRatioAfter"] > 0).all()
        max_injection_error, max_product_error = max(max_injection_error, inj), max(max_product_error, product)
        for column in ("RPM", "SpeedMPH", "Gear"):
            np.testing.assert_allclose(data[column][~active], base[column][~active], rtol=0, atol=1e-7)
        m = metrics(data, target["DeadlineSeconds"], target["TargetSpeedMPH"])
        for key, value in m.items():
            if isinstance(value, bool):
                assert bool(int(row[key])) == value, (case, inp, key)
            else:
                np.testing.assert_allclose(float(row[key]), value, rtol=0, atol=1e-9, equal_nan=True)
        passed = m["AccelerationPass"] and m["GearRangePass"] and m["GearDiscretePass"]
        assert bool(int(row["Pass"])) == passed
        if case == "B00":
            assert passed and m["AccelerationRhoMPH"] >= spec["BaselineClearanceMPH"]
        else:
            off_path = root / "checks" / f"{case}_{inp}_off.mat"
            if off_path.exists():
                off = loadmat(off_path, simplify_cells=True)
                normal_y = np.column_stack([base[col] for col in ("RPM", "SpeedMPH", "Gear")])
                off_error = float(np.max(np.abs(off["off"]["Y"] - normal_y)))
                assert off_error < 1e-7 and abs(off_error - float(off["offError"])) < 1e-10
                max_off_error = max(max_off_error, off_error)
        violated = case != "B00" and not passed
        assert bool(int(row["FaultInducedViolation"])) == violated
        counts[case] += int(violated)
        results.append({"Case": case, "Input": inp, "AccelerationRhoMPH": m["AccelerationRhoMPH"],
                        "FaultInducedViolation": violated})
    checked_off = len(list((root / "checks").glob("*_off.mat")))
    assert checked_off == 18, "All 18 disabled-fault replay checks are required"
    hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(root.rglob("*.csv")) if "generation_" not in str(p)}
    return {"Status": "PASS", "CSVTraces": len(traces), "SamplesPerTrace": 3001,
            "PrimarySimulations": 24, "FaultOffChecksPresent": checked_off,
            "TargetSpeedMPH": target["TargetSpeedMPH"], "DeadlineSeconds": target["DeadlineSeconds"],
            "ViolationsByCase": counts, "MaximumInjectionError": float(max_injection_error),
            "MaximumTorqueProductError": float(max_product_error), "MaximumOffReplayError": max_off_error,
            "Results": results, "SHA256": hashes,
            "Scope": "Six fixed pilot inputs; not tool performance or an all-input safety proof."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = audit(args.run_directory)
    if args.output:
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in result.items() if k not in ("Results", "SHA256")}, indent=2))


if __name__ == "__main__":
    main()
