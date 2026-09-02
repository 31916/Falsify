#!/usr/bin/env python3
"""Run and aggregate a small, reproducible ARCH-COMP 2025 RL pilot.

The default experiment compares RAND, A3C, ACER, and DDQN on CC3
Instance 2 with the same three random seeds and at most 30 episodes.
Each run is delegated to validate_arch2025_all.m so input validation,
official-model replay, and STL robustness calculation stay identical to
the unified 188-case pipeline.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


DEFAULT_MATLAB = Path("/Applications/MATLAB_R2026a.app/bin/matlab")
DEFAULT_ALGORITHMS = ("RAND", "A3C", "ACER", "DDQN")
DEFAULT_SEEDS = (20250903, 20250904, 20250905)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--case-prefix",
        default="cc_cc3_i2",
        help="CaseID without its algorithm suffix (default: cc_cc3_i2).",
    )
    parser.add_argument(
        "--algorithms",
        nargs="+",
        default=list(DEFAULT_ALGORITHMS),
        choices=DEFAULT_ALGORITHMS,
    )
    parser.add_argument(
        "--seeds",
        nargs="+",
        type=int,
        default=list(DEFAULT_SEEDS),
    )
    parser.add_argument("--episodes", type=int, default=30)
    parser.add_argument("--matlab", type=Path, default=DEFAULT_MATLAB)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=None,
        help="Output directory (default: results/arch2025/pilots/<timestamp>).",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-run combinations whose result CSV already exists.",
    )
    parser.add_argument(
        "--rebuild-wrappers",
        action="store_true",
        help="Rebuild generated wrappers before the first executed run.",
    )
    args = parser.parse_args()
    if args.episodes < 1:
        parser.error("--episodes must be at least 1")
    if any(seed < 0 or seed > 2**31 - 1 for seed in args.seeds):
        parser.error("each seed must be between 0 and 2^31-1")
    return args


def matlab_string(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def read_single_result(summary_file: Path) -> dict[str, str]:
    with summary_file.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 1:
        raise RuntimeError(
            f"expected one result row in {summary_file}, found {len(rows)}"
        )
    return rows[0]


def float_or_nan(value: str | None) -> float:
    try:
        return float(value or "nan")
    except ValueError:
        return float("nan")


def bool_text(value: str | None) -> bool:
    return str(value).strip().lower() in {"1", "true", "yes"}


def median_or_nan(values: list[float]) -> float:
    finite = [value for value in values if value == value]
    return statistics.median(finite) if finite else float("nan")


def quartiles_or_nan(values: list[float]) -> tuple[float, float]:
    finite = sorted(value for value in values if value == value)
    if not finite:
        return float("nan"), float("nan")
    if len(finite) == 1:
        return finite[0], finite[0]
    quartiles = statistics.quantiles(finite, n=4, method="inclusive")
    return quartiles[0], quartiles[2]


def wilson_interval(successes: int, trials: int) -> tuple[float, float]:
    if trials == 0:
        return float("nan"), float("nan")
    z = 1.959963984540054
    proportion = successes / trials
    denominator = 1 + z**2 / trials
    center = (proportion + z**2 / (2 * trials)) / denominator
    radius = (
        z
        * math.sqrt(
            proportion * (1 - proportion) / trials
            + z**2 / (4 * trials**2)
        )
        / denominator
    )
    return max(0.0, center - radius), min(1.0, center + radius)


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(rows[0]),
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def aggregate(rows: list[dict[str, object]], algorithms: list[str]) -> list[dict[str, object]]:
    summary: list[dict[str, object]] = []
    for algorithm in algorithms:
        selected = [row for row in rows if row["Algorithm"] == algorithm]
        valid = [
            row
            for row in selected
            if row["Status"] == "VALIDATED"
            and row["OverallPass"]
            and row["MatlabReturnCode"] == 0
        ]
        violations = [
            row for row in valid if row["OfficialClassification"] == "VIOLATED"
        ]
        rate_low, rate_high = wilson_interval(len(violations), len(valid))
        episode_q1, episode_q3 = quartiles_or_nan(
            [float(row["Episodes"]) for row in valid]
        )
        seconds_q1, seconds_q3 = quartiles_or_nan(
            [float(row["FalsifyElapsedSeconds"]) for row in valid]
        )
        summary.append(
            {
                "Algorithm": algorithm,
                "Runs": len(selected),
                "ValidatedRuns": len(valid),
                "OfficialViolations": len(violations),
                "OfficialViolationRate": (
                    len(violations) / len(valid) if valid else float("nan")
                ),
                "OfficialViolationRateCI95Low": rate_low,
                "OfficialViolationRateCI95High": rate_high,
                "MedianEpisodesAll": median_or_nan(
                    [float(row["Episodes"]) for row in valid]
                ),
                "EpisodeQ1": episode_q1,
                "EpisodeQ3": episode_q3,
                "MedianEpisodesToViolation": median_or_nan(
                    [float(row["Episodes"]) for row in violations]
                ),
                "MedianFalsifySeconds": median_or_nan(
                    [float(row["FalsifyElapsedSeconds"]) for row in valid]
                ),
                "FalsifySecondsQ1": seconds_q1,
                "FalsifySecondsQ3": seconds_q3,
                "MedianWallSeconds": median_or_nan(
                    [float(row["WallSeconds"]) for row in selected]
                ),
                "MedianOfficialRobustness": median_or_nan(
                    [float(row["OfficialRobustness"]) for row in valid]
                ),
            }
        )
    return summary


def main() -> int:
    args = parse_args()
    repo = Path(__file__).resolve().parent
    matlab = args.matlab.expanduser().resolve()
    if not matlab.is_file():
        raise FileNotFoundError(f"MATLAB executable not found: {matlab}")

    output_root = args.output_root
    if output_root is None:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_root = repo / "results" / "arch2025" / "pilots" / stamp
    elif not output_root.is_absolute():
        output_root = repo / output_root
    output_root = output_root.resolve()
    output_root.mkdir(parents=True, exist_ok=True)

    git_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=repo,
        check=False,
        capture_output=True,
        text=True,
    ).stdout.strip()
    git_status = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=repo,
        check=False,
        capture_output=True,
        text=True,
    ).stdout.splitlines()
    source_files = [
        "driver.py",
        "falsify.m",
        "validate_arch2025_all.m",
        Path(__file__).name,
    ]
    source_sha256 = {
        source_file: sha256_file(repo / source_file)
        for source_file in source_files
    }

    manifest = {
        "case_prefix": args.case_prefix,
        "algorithms": args.algorithms,
        "seeds": args.seeds,
        "max_episodes": args.episodes,
        "matlab": str(matlab),
        "git_commit": git_commit,
        "git_worktree_dirty": bool(git_status),
        "git_dirty_entries": git_status,
        "source_sha256": source_sha256,
        "rebuild_wrappers_before_first_run": args.rebuild_wrappers,
        "started_at": datetime.now().astimezone().isoformat(),
    }
    (output_root / "pilot_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    rows: list[dict[str, object]] = []
    combinations = [
        (algorithm, seed)
        for algorithm in args.algorithms
        for seed in args.seeds
    ]

    for run_index, (algorithm, seed) in enumerate(combinations, start=1):
        case_id = f"{args.case_prefix}_{algorithm.lower()}"
        run_directory = output_root / f"{algorithm.lower()}_seed_{seed}"
        summary_file = run_directory / "arch2025_all_summary.csv"
        log_file = run_directory / "matlab.log"
        run_directory.mkdir(parents=True, exist_ok=True)

        print(
            f"[{run_index}/{len(combinations)}] {case_id}, seed={seed}, "
            f"episodes={args.episodes}",
            flush=True,
        )

        wall_start = time.monotonic()
        return_code = 0
        if args.force or not summary_file.is_file():
            settings = {
                "FALSIFY_ARCH2025_CASE_FILTER": case_id,
                "FALSIFY_ARCH2025_RESUME_PASSED": "0",
                "FALSIFY_ARCH2025_REBUILD_WRAPPERS": "0",
                "FALSIFY_ARCH2025_MAX_EPISODES": str(args.episodes),
                "FALSIFY_ARCH2025_SEED_OVERRIDE": str(seed),
                "FALSIFY_ARCH2025_OUTPUT_DIR": str(run_directory),
            }
            if args.rebuild_wrappers and run_index == 1:
                settings["FALSIFY_ARCH2025_REBUILD_WRAPPERS"] = "1"
            expression = "; ".join(
                f"setenv({matlab_string(name)},{matlab_string(value)})"
                for name, value in settings.items()
            )
            expression += "; validate_arch2025_all"
            with log_file.open("w", encoding="utf-8") as log_handle:
                completed = subprocess.run(
                    [str(matlab), "-batch", expression],
                    cwd=repo,
                    stdout=log_handle,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
            return_code = completed.returncode
        wall_seconds = time.monotonic() - wall_start

        try:
            source = read_single_result(summary_file)
            row: dict[str, object] = {
                "CaseID": source.get("CaseID", case_id),
                "Algorithm": algorithm,
                "Seed": seed,
                "Status": source.get("Status", "MISSING"),
                "Episodes": float_or_nan(source.get("Episodes")),
                "FalsifyElapsedSeconds": float_or_nan(
                    source.get("ElapsedSeconds")
                ),
                "WallSeconds": wall_seconds,
                "FalsifyRobustness": float_or_nan(
                    source.get("FalsifyRobustness")
                ),
                "OfficialRobustness": float_or_nan(
                    source.get("OfficialRobustness")
                ),
                "OfficialClassification": source.get(
                    "OfficialClassification", ""
                ),
                "OverallPass": bool_text(source.get("OverallPass")),
                "TrajectoryEquivalencePass": bool_text(
                    source.get("TrajectoryEquivalencePass")
                ),
                "MatlabReturnCode": return_code,
                "RunDirectory": str(run_directory.relative_to(repo)),
                "ErrorIdentifier": source.get("ErrorIdentifier", ""),
                "ErrorMessage": source.get("ErrorMessage", ""),
            }
        except Exception as error:  # preserve a failed run for aggregation
            row = {
                "CaseID": case_id,
                "Algorithm": algorithm,
                "Seed": seed,
                "Status": "RUNNER_ERROR",
                "Episodes": float("nan"),
                "FalsifyElapsedSeconds": float("nan"),
                "WallSeconds": wall_seconds,
                "FalsifyRobustness": float("nan"),
                "OfficialRobustness": float("nan"),
                "OfficialClassification": "",
                "OverallPass": False,
                "TrajectoryEquivalencePass": False,
                "MatlabReturnCode": return_code,
                "RunDirectory": str(run_directory.relative_to(repo)),
                "ErrorIdentifier": type(error).__name__,
                "ErrorMessage": str(error),
            }
        rows.append(row)
        write_csv(output_root / "pilot_runs.csv", rows)

    summary = aggregate(rows, args.algorithms)
    write_csv(output_root / "pilot_summary.csv", summary)
    manifest["completed_at"] = datetime.now().astimezone().isoformat()
    manifest["run_count"] = len(rows)
    manifest["validated_run_count"] = sum(
        row["Status"] == "VALIDATED" for row in rows
    )
    (output_root / "pilot_manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Run table: {output_root / 'pilot_runs.csv'}")
    print(f"Summary:   {output_root / 'pilot_summary.csv'}")
    return 0 if all(
        row["Status"] == "VALIDATED"
        and row["OverallPass"]
        and row["MatlabReturnCode"] == 0
        for row in rows
    ) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        print("Interrupted", file=sys.stderr)
        raise SystemExit(130)
