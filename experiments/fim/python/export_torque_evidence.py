"""Export audited pilot evidence without redistributing licensed models/data.

The destination must be new. Full primary CSV traces and disabled-fault MAT
checks are included, so the independent auditor can rerun on this directory.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

from audit_torque_acceleration import audit


def export(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    assert source != destination and not destination.exists(), "Use a new evidence directory"
    result = audit(source)
    assert result["Status"] == "PASS" and result["FaultOffChecksPresent"] == 18
    destination.mkdir(parents=True)
    for name in ("inputs.csv", "target.json", "summary.csv", "fault_catalog.csv"):
        shutil.copy2(source / name, destination / name)
    for folder, pattern in (("traces", "*.csv"), ("checks", "*_off.mat")):
        (destination / folder).mkdir()
        for path in sorted((source / folder).glob(pattern)):
            shutil.copy2(path, destination / folder / path.name)
    manifest = json.loads((source / "manifest.json").read_text())
    manifest["Source"] = ".deps/fim/arch/models/FALS/transmission/Autotrans_shift.mdl"
    manifest["RunID"] = source.name
    manifest["ExecutionSourceSHA256"] = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((source / "code_snapshot").iterdir()) if p.is_file()}
    manifest["AuditSourceSHA256"] = hashlib.sha256(
        Path(__file__).with_name("audit_torque_acceleration.py").read_bytes()).hexdigest()
    manifest["Export"] = "All 24 primary CSV traces and 18 disabled-fault checks; no licensed models/data"
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    for case in ("T01", "T02", "T03"):
        generation = source / f"generation_{case}"
        for subfolder, pattern in (("Configuration", "*.csv"), ("fault_table", "*.xls")):
            out = destination / generation.name / subfolder
            out.mkdir(parents=True)
            for path in sorted((generation / subfolder).glob(pattern)):
                shutil.copy2(path, out / path.name)
    # Recompute against the exported evidence rather than copying a PASS label.
    result = audit(destination)
    (destination / "audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"Exported and audited {result['CSVTraces']} traces: {destination}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_directory", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    export(args.run_directory, args.destination)
