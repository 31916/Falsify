"""Independently audit saved FIM trajectories; no MATLAB or model edits."""
import argparse
import csv
from pathlib import Path

import numpy as np
from scipy.io import loadmat


def rows(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def audit_trace(trace):
    t = np.asarray(trace["T"]).reshape(-1)
    y = np.asarray(trace["Y"])
    u = np.asarray(trace["U"])
    assert t.shape == (3001,) and y.shape == (3001, 3)
    assert np.allclose(t, np.arange(3001) / 100, atol=1e-10, rtol=0)
    assert np.isfinite(y).all() and np.isfinite(u).all()
    assert u[0, 0] == 0 and u[-1, 0] == 30
    assert (np.diff(u[:, 0]) > 0).all()
    assert (u[:, 1:] >= -1e-9).all()
    assert (u[:, 1:] <= np.array([100, 325]) + 1e-9).all()
    changes = np.r_[True, np.any(np.abs(np.diff(u[:, 1:], axis=0)) > 1e-9, axis=1)]
    assert np.allclose(u[changes, 0] / 5, np.rint(u[changes, 0] / 5), atol=1e-8, rtol=0)
    margins = np.column_stack((y[:, 0] - 599, 6001 - y[:, 0], y[:, 2] - 0.5, 4.5 - y[:, 2])).min(axis=0)
    rho = (margins / [3000, 3000, 1.5, 1.5]).min()
    assert abs(float(trace["Rho"]) - rho) < 1e-10
    assert np.allclose(trace["ClauseMargins"], margins, atol=1e-8)
    return float(rho)


def audit_pair(trace, baseline, case, catalog):
    rho = audit_trace(trace)
    assert audit_trace(baseline) > 0
    assert np.array_equal(trace["U"], baseline["U"])
    y = baseline["Y"]
    assert (y[:, 0] >= 600 - 1e-8).all() and (y[:, 0] <= 6000 + 1e-8).all()
    assert np.isin(y[:, 2], [1, 2, 3, 4]).all()
    before = trace["T"] < 5 - 1e-10
    assert np.allclose(trace["Y"][before], y[before], rtol=0, atol=1e-7)
    if case != "B00":
        injected = trace["Injected"]
        expected = np.array(injected["Before"], dtype=float, copy=True)
        active = np.asarray(injected["T"]) >= 5 - 1e-10
        fault = catalog[case]
        if fault["Type"] == "Bias/Offset":
            expected[active] += float(fault["Value"])
        elif fault["Type"] == "Negate":
            expected[active] *= -1
        elif fault["Type"] == "Stuck-at 0":
            expected[active] = 0
        else:
            raise AssertionError("Unknown fault operator")
        assert np.allclose(expected, injected["After"], rtol=0, atol=1e-7)
    return rho


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("run_directory", type=Path)
    root = parser.parse_args().run_directory.resolve()
    catalog = {r["ID"]: r for r in rows(root / "fault_catalog.csv")}
    exp1 = rows(root / "experiment1.csv")
    exp2 = rows(root / "experiment2.csv")
    assert len(catalog) == 10 and len(exp1) == 132 and len(exp2) == 66
    assert len({(r["Case"], r["Input"]) for r in exp1}) == 132
    assert len({(r["Case"], r["Algorithm"], r["Seed"]) for r in exp2}) == 66
    for row in exp1:
        data = loadmat(root / "exp1" / f'{row["Case"]}_{row["Input"]}.mat', simplify_cells=True)
        rho = audit_pair(data["trace"], data["baseline"], row["Case"], catalog)
        assert abs(rho - float(row["Rho"])) < 1e-10
        assert int(row["Violated"]) == (rho < -1e-9)
        assert float(row["FaultOffMaxError"]) < 1e-7
    count = 0
    max_error = 0
    for row in exp2:
        folder = Path(row["CandidateDirectory"]).resolve()
        assert root in folder.parents
        files = sorted(folder.glob("episode_*.mat"))
        assert len(files) == int(row["Episodes"])
        robustness = []
        for file in files:
            data = loadmat(file, simplify_cells=True)
            rho = audit_pair(data["trace"], data["normal"], row["Case"], catalog)
            robustness.append(rho)
            error = float(data["err"])
            assert error < 1e-5
            max_error = max(max_error, error)
            count += 1
        assert abs(min(robustness) - float(row["Rho"])) < 1e-10
        assert int(row["Violated"]) == (min(robustness) < -1e-9)
        assert 1 <= len(files) <= 10
        if min(robustness) < -1e-9:
            assert robustness[-1] < -1e-9 and all(r >= 0 for r in robustness[:-1])
        else:
            assert len(files) == 10
    print(f"PASS: 132 comparisons, 66 searches, {count} independently audited candidates.")
    print(f"Maximum wrapper/replay difference over ALL candidates: {max_error:.12g}")
    print("All baseline traces satisfy the invariant; all active FIM operations match the catalog.")


if __name__ == "__main__":
    main()
