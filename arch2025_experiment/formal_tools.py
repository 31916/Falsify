#!/usr/bin/env python3

import argparse
import csv
import json
import math
import os
import re
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


ALGORITHMS = ["RAND", "A3C", "ACER", "DDQN"]
MODELS = ["SB", "AT", "AFC", "CC", "NN", "F16", "SC"]
SEEDS = list(range(20250001, 20250011))
MAX_EVALUATIONS = 1500


def atomic_text(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    os.replace(temporary, path)


def atomic_json(path, value):
    atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def rotate(values, amount):
    if not values:
        return []
    amount %= len(values)
    return values[amount:] + values[:amount]


def truthy(value):
    return str(value).strip().lower() in {"1", "true", "yes"}


def number(value):
    try:
        result = float(value)
    except (TypeError, ValueError):
        return math.nan
    return result


def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def write_csv(path, rows, fields):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    os.replace(temporary, path)


def build_manifest(args):
    catalog = read_csv(args.catalog)
    if len(catalog) != 196:
        raise ValueError(f"catalog must contain 196 rows, found {len(catalog)}")
    case_ids = [row["CaseID"] for row in catalog]
    if len(set(case_ids)) != 196:
        raise ValueError("catalog CaseID values are not unique")

    by_condition = defaultdict(dict)
    condition_order = []
    for row in catalog:
        condition = (row["Model"], row["Requirement"], row["Instance"])
        if condition not in by_condition:
            condition_order.append(condition)
        algorithm = row["Algorithm"]
        if algorithm in by_condition[condition]:
            raise ValueError(f"duplicate condition/algorithm: {condition} {algorithm}")
        by_condition[condition][algorithm] = row

    if len(condition_order) != 49:
        raise ValueError(f"catalog must contain 49 conditions, found {len(condition_order)}")
    for condition, algorithms in by_condition.items():
        if set(algorithms) != set(ALGORITHMS):
            raise ValueError(f"algorithm set mismatch for {condition}: {sorted(algorithms)}")

    rows = []
    sequence = 0
    for seed_index, seed in enumerate(SEEDS, start=1):
        model_order = rotate(MODELS, seed_index - 1)
        algorithm_order = rotate(ALGORITHMS, seed_index - 1)
        for model in model_order:
            model_conditions = [item for item in condition_order if item[0] == model]
            model_conditions = rotate(model_conditions, seed_index - 1)
            batch_id = f"s{seed_index:02d}_{model.lower()}"
            for condition in model_conditions:
                for algorithm in algorithm_order:
                    sequence += 1
                    catalog_row = by_condition[condition][algorithm]
                    case_id = catalog_row["CaseID"]
                    rows.append({
                        "Sequence": sequence,
                        "BatchID": batch_id,
                        "SeedIndex": seed_index,
                        "Seed": seed,
                        "TrialID": f"s{seed_index:02d}_{case_id}",
                        "CaseID": case_id,
                        "Model": catalog_row["Model"],
                        "Requirement": catalog_row["Requirement"],
                        "Instance": catalog_row["Instance"],
                        "Algorithm": algorithm,
                        "MaxEvaluations": MAX_EVALUATIONS,
                    })

    if len(rows) != 1960:
        raise ValueError(f"manifest must contain 1960 trials, found {len(rows)}")
    fields = list(rows[0])
    write_csv(args.output, rows, fields)
    seeds_path = Path(args.output).with_name("seeds.txt")
    atomic_text(seeds_path, "\n".join(map(str, SEEDS)) + "\n")
    plan = {
        "CreatedAtUTC": datetime.now(timezone.utc).isoformat(),
        "Catalog": str(Path(args.catalog).resolve()),
        "CatalogRows": len(catalog),
        "Conditions": len(condition_order),
        "Algorithms": ALGORITHMS,
        "Seeds": SEEDS,
        "Trials": len(rows),
        "MaxEvaluationsPerTrial": MAX_EVALUATIONS,
        "MaximumSearchSimulations": len(rows) * MAX_EVALUATIONS,
        "BatchCount": len(set(row["BatchID"] for row in rows)),
        "Ordering": "Seed-specific cyclic rotation of model, condition, and algorithm order.",
    }
    atomic_json(Path(args.output).with_name("plan.json"), plan)


def list_pending(args):
    rows = read_csv(args.manifest)
    selected = [row for row in rows if row["BatchID"] == args.batch]
    if not selected:
        raise ValueError(f"unknown or empty batch: {args.batch}")
    fields = [
        "Sequence", "BatchID", "SeedIndex", "Seed", "TrialID", "CaseID",
        "Model", "Requirement", "Instance", "Algorithm", "MaxEvaluations",
    ]
    writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
    for row in selected:
        complete = Path(args.run_root) / row["TrialID"] / "complete.json"
        if not complete.is_file():
            writer.writerow([row[field] for field in fields])


def parse_time_file(path):
    output = {"TotalWallSeconds": math.nan, "MaximumRSSKiB": math.nan}
    path = Path(path)
    if not path.is_file():
        return output
    text = path.read_text(encoding="utf-8", errors="replace")
    wall_match = re.search(
        r"Elapsed \(wall clock\) time \(h:mm:ss or m:ss\):\s*([^\n]+)",
        text,
    )
    rss_match = re.search(r"Maximum resident set size \(kbytes\):\s*(\d+)", text)
    if wall_match:
        parts = wall_match.group(1).strip().split(":")
        try:
            if len(parts) == 3:
                output["TotalWallSeconds"] = int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
            elif len(parts) == 2:
                output["TotalWallSeconds"] = int(parts[0]) * 60 + float(parts[1])
        except ValueError:
            pass
    if rss_match:
        output["MaximumRSSKiB"] = int(rss_match.group(1))
    return output


def validate_attempt(args):
    errors = []
    row = {}
    if int(args.matlab_exit) != 0:
        errors.append(f"MATLAB exit code was {args.matlab_exit}")
    try:
        rows = read_csv(args.summary)
    except Exception as error:
        rows = []
        errors.append(f"could not read summary: {error}")
    if len(rows) != 1:
        errors.append(f"summary row count was {len(rows)}, expected 1")
    else:
        row = rows[0]
        if row.get("CaseID") != args.case_id:
            errors.append("CaseID mismatch")
        try:
            actual_seed = int(float(row.get("Seed", "nan")))
        except ValueError:
            actual_seed = -1
        if actual_seed != int(args.seed):
            errors.append("Seed mismatch")
        if row.get("Status") not in {"VALIDATED", "COMPLETE_MISMATCH"}:
            errors.append(f"Status was {row.get('Status')}")
        if not truthy(row.get("TrialComplete")):
            errors.append("TrialComplete was false")
        if not truthy(row.get("InputPass")):
            errors.append("InputPass was false")
        if not truthy(row.get("FalsifyRunPass")):
            errors.append("FalsifyRunPass was false")
        if not truthy(row.get("OfficialReplayPass")):
            errors.append("OfficialReplayPass was false")

        try:
            episodes = int(float(row.get("Episodes", "nan")))
        except ValueError:
            episodes = -1
        if not 1 <= episodes <= int(args.max_evaluations):
            errors.append(f"Episodes was {episodes}")
        falsify_robustness = number(row.get("FalsifyRobustness"))
        if episodes < int(args.max_evaluations) and not falsify_robustness < 0:
            errors.append("early termination occurred without negative FalsifyRobustness")

    timing = parse_time_file(args.time_file)
    status = {
        "CheckedAtUTC": datetime.now(timezone.utc).isoformat(),
        "Outcome": "COMPLETE" if not errors else "ERROR",
        "ValidationErrors": errors,
        "TrialID": args.trial_id,
        "BatchID": args.batch_id,
        "Sequence": int(args.sequence),
        "CaseID": args.case_id,
        "Seed": int(args.seed),
        "MaxEvaluations": int(args.max_evaluations),
        "MatlabExitCode": int(args.matlab_exit),
        "SummaryFile": str(Path(args.summary).resolve()),
        "MatlabLog": str(Path(args.matlab_log).resolve()),
        "TimeFile": str(Path(args.time_file).resolve()),
        **timing,
    }
    if row:
        episodes = int(float(row.get("Episodes", 0) or 0))
        official_robustness = number(row.get("OfficialRobustness"))
        reported_counterexample = number(row.get("FalsifyRobustness")) < 0
        official_counterexample = official_robustness < 0
        status.update({
            "Episodes": episodes,
            "EarlyStopped": episodes < int(args.max_evaluations),
            "FalsifyRobustness": number(row.get("FalsifyRobustness")),
            "FalsifyReportedCounterexample": reported_counterexample,
            "OfficialRobustness": official_robustness,
            "OfficialCounterexample": official_counterexample,
            "OfficialValidatedCounterexample": (
                reported_counterexample and official_counterexample
            ),
            "ClassificationAgreementPass": truthy(row.get("ClassificationAgreementPass")),
            "OfficialClassification": row.get("OfficialClassification", ""),
        })
    atomic_json(args.attempt_status, status)
    if not errors:
        atomic_json(args.complete, status)
        return 0
    return 1


def finite_values(rows, field):
    values = [number(row.get(field)) for row in rows]
    return [value for value in values if math.isfinite(value)]


def safe_stat(values, operation):
    return operation(values) if values else math.nan


def aggregate(args):
    manifest = read_csv(args.manifest)
    manifest_by_id = {row["TrialID"]: row for row in manifest}
    run_root = Path(args.run_root)
    output = Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    completed = []
    mismatches = []
    reported_counterexamples = []
    official_counterexamples = []
    validated_counterexamples = []
    for complete_path in sorted(run_root.glob("*/complete.json")):
        complete = json.loads(complete_path.read_text(encoding="utf-8"))
        trial_id = complete["TrialID"]
        trial = manifest_by_id[trial_id]
        summary_rows = read_csv(complete["SummaryFile"])
        if len(summary_rows) != 1:
            continue
        source = summary_rows[0]
        timing = parse_time_file(complete["TimeFile"])
        merged = dict(trial)
        merged.update({
            "ActualEvaluations": source.get("Episodes", ""),
            "EarlyStopped": str(complete.get("EarlyStopped", False)).lower(),
            "FalsifyReportedCounterexample": str(complete.get("FalsifyReportedCounterexample", False)).lower(),
            "OfficialCounterexample": str(complete.get("OfficialCounterexample", False)).lower(),
            "OfficialValidatedCounterexample": str(
                complete.get("OfficialValidatedCounterexample", False)
            ).lower(),
            "TotalWallSeconds": timing["TotalWallSeconds"],
            "MaximumRSSKiB": timing["MaximumRSSKiB"],
            "SummaryFile": complete["SummaryFile"],
            "MatlabLog": complete["MatlabLog"],
            "TimeFile": complete["TimeFile"],
        })
        merged.update(source)
        completed.append(merged)
        if not truthy(source.get("ClassificationAgreementPass")):
            mismatches.append(merged)
        if complete.get("FalsifyReportedCounterexample", False):
            reported_counterexamples.append(merged)
        if complete.get("OfficialCounterexample", False):
            official_counterexamples.append(merged)
        if complete.get("OfficialValidatedCounterexample", False):
            validated_counterexamples.append(merged)

    completed.sort(key=lambda row: int(row["Sequence"]))
    all_fields = [
        "Sequence", "BatchID", "SeedIndex", "TrialID", "CaseID", "Model",
        "Requirement", "Instance", "Algorithm", "Seed", "MaxEvaluations",
        "ActualEvaluations", "EarlyStopped", "Status", "FalsifyRobustness",
        "FalsifyClassification", "FalsifyReportedCounterexample",
        "OfficialRobustness", "OfficialClassification",
        "OfficialCounterexample", "OfficialValidatedCounterexample",
        "InputRangePass", "InputStructurePass", "InputPass",
        "FalsifyRunPass", "OfficialReplayPass", "ClassificationAgreementPass",
        "TrajectoryEquivalencePass", "OverallPass", "ElapsedSeconds",
        "TotalWallSeconds", "MaximumRSSKiB", "InputTraceFile", "StateTraceFile",
        "ErrorIdentifier", "ErrorMessage", "SummaryFile", "MatlabLog", "TimeFile",
    ]
    write_csv(output / "all_trials.csv", completed, all_fields)
    write_csv(output / "classification_mismatches.csv", mismatches, all_fields)
    write_csv(output / "official_counterexamples.csv", official_counterexamples, all_fields)
    write_csv(
        output / "official_validated_counterexamples.csv",
        validated_counterexamples,
        all_fields,
    )

    error_rows = []
    for status_path in sorted(Path(args.manifest_root).glob("*/attempt-*/attempt-status.json")):
        status = json.loads(status_path.read_text(encoding="utf-8"))
        if status.get("Outcome") != "COMPLETE":
            error_rows.append({
                "TrialID": status.get("TrialID", ""),
                "BatchID": status.get("BatchID", ""),
                "CaseID": status.get("CaseID", ""),
                "Seed": status.get("Seed", ""),
                "MatlabExitCode": status.get("MatlabExitCode", ""),
                "ValidationErrors": " | ".join(status.get("ValidationErrors", [])),
                "AttemptStatusFile": str(status_path.resolve()),
                "MatlabLog": status.get("MatlabLog", ""),
            })
    error_fields = ["TrialID", "BatchID", "CaseID", "Seed", "MatlabExitCode", "ValidationErrors", "AttemptStatusFile", "MatlabLog"]
    write_csv(output / "errors.csv", error_rows, error_fields)

    groups = defaultdict(list)
    for row in completed:
        groups[(row["Model"], row["Requirement"], row["Instance"], row["Algorithm"])].append(row)
    summary_rows = []
    for key in sorted(groups):
        rows = groups[key]
        reported = [row for row in rows if str(row["FalsifyReportedCounterexample"]).lower() == "true"]
        counterexamples = [row for row in rows if str(row["OfficialCounterexample"]).lower() == "true"]
        validated = [
            row for row in rows
            if str(row["OfficialValidatedCounterexample"]).lower() == "true"
        ]
        successful_evaluations = finite_values(counterexamples, "ActualEvaluations")
        validated_evaluations = finite_values(validated, "ActualEvaluations")
        wall = finite_values(rows, "TotalWallSeconds")
        robustness = finite_values(rows, "OfficialRobustness")
        summary_rows.append({
            "Model": key[0],
            "Requirement": key[1],
            "Instance": key[2],
            "Algorithm": key[3],
            "PlannedTrials": 10,
            "CompletedTrials": len(rows),
            "FalsifyReportedCounterexamples": len(reported),
            "FalsifyReportedRateCompleted": len(reported) / len(rows) if rows else math.nan,
            "FalsifyReportedRatePlanned": len(reported) / 10,
            "OfficialCounterexamples": len(counterexamples),
            "OfficialFalsificationRateCompleted": len(counterexamples) / len(rows) if rows else math.nan,
            "OfficialFalsificationRatePlanned": len(counterexamples) / 10,
            "OfficialValidatedCounterexamples": len(validated),
            "OfficialValidatedFalsificationRateCompleted": len(validated) / len(rows) if rows else math.nan,
            "OfficialValidatedFalsificationRatePlanned": len(validated) / 10,
            "MeanEvaluationsOfficialCounterexamplesOnly": safe_stat(successful_evaluations, statistics.mean),
            "MedianEvaluationsOfficialCounterexamplesOnly": safe_stat(successful_evaluations, statistics.median),
            "MeanEvaluationsValidatedOnly": safe_stat(validated_evaluations, statistics.mean),
            "MedianEvaluationsValidatedOnly": safe_stat(validated_evaluations, statistics.median),
            "MeanWallSeconds": safe_stat(wall, statistics.mean),
            "MedianWallSeconds": safe_stat(wall, statistics.median),
            "MinOfficialRobustness": safe_stat(robustness, min),
            "MedianOfficialRobustness": safe_stat(robustness, statistics.median),
            "MeanOfficialRobustness": safe_stat(robustness, statistics.mean),
            "MaxOfficialRobustness": safe_stat(robustness, max),
            "ClassificationMismatches": sum(not truthy(row.get("ClassificationAgreementPass")) for row in rows),
        })
    summary_fields = list(summary_rows[0]) if summary_rows else [
        "Model", "Requirement", "Instance", "Algorithm", "PlannedTrials", "CompletedTrials"
    ]
    write_csv(output / "condition_algorithm_summary.csv", summary_rows, summary_fields)

    completed_ids = {row["TrialID"] for row in completed}
    model_completed = Counter(row["Model"] for row in completed)
    report = [
        "# Falsify × ARCH-COMP 2025 formal experiment progress",
        "",
        f"Generated: {datetime.now(timezone.utc).isoformat()}",
        f"Completed trials: {len(completed)} / {len(manifest)}",
        f"Remaining trials: {len(manifest) - len(completed_ids)}",
        f"Error attempts: {len(error_rows)}",
        f"Falsify-reported counterexamples: {len(reported_counterexamples)}",
        f"Official counterexamples: {len(official_counterexamples)}",
        f"Official-validated reported counterexamples: {len(validated_counterexamples)}",
        f"Classification mismatches among completed trials: {len(mismatches)}",
        "",
        "## Completed by model",
        "",
    ]
    planned_by_model = Counter(row["Model"] for row in manifest)
    for model in MODELS:
        report.append(f"- {model}: {model_completed[model]} / {planned_by_model[model]}")
    report.extend([
        "",
        "Final counterexample decisions use OfficialRobustness. Evaluation means and medians use successful official-counterexample trials only.",
    ])
    atomic_text(output / "progress_report.md", "\n".join(report) + "\n")


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build-manifest")
    build.add_argument("--catalog", required=True)
    build.add_argument("--output", required=True)
    build.set_defaults(function=build_manifest)

    pending = subparsers.add_parser("pending")
    pending.add_argument("--manifest", required=True)
    pending.add_argument("--batch", required=True)
    pending.add_argument("--run-root", required=True)
    pending.set_defaults(function=list_pending)

    validate = subparsers.add_parser("validate-attempt")
    validate.add_argument("--summary", required=True)
    validate.add_argument("--case-id", required=True)
    validate.add_argument("--seed", required=True)
    validate.add_argument("--max-evaluations", required=True)
    validate.add_argument("--matlab-exit", required=True)
    validate.add_argument("--trial-id", required=True)
    validate.add_argument("--batch-id", required=True)
    validate.add_argument("--sequence", required=True)
    validate.add_argument("--time-file", required=True)
    validate.add_argument("--matlab-log", required=True)
    validate.add_argument("--attempt-status", required=True)
    validate.add_argument("--complete", required=True)
    validate.set_defaults(function=validate_attempt)

    aggregate_parser = subparsers.add_parser("aggregate")
    aggregate_parser.add_argument("--manifest", required=True)
    aggregate_parser.add_argument("--run-root", required=True)
    aggregate_parser.add_argument("--manifest-root", required=True)
    aggregate_parser.add_argument("--output", required=True)
    aggregate_parser.set_defaults(function=aggregate)

    args = parser.parse_args()
    try:
        result = args.function(args)
    except Exception as error:
        print(f"formal_tools error: {error}", file=sys.stderr)
        return 2
    return 0 if result is None else int(result)


if __name__ == "__main__":
    raise SystemExit(main())
