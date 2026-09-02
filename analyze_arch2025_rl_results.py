#!/usr/bin/env python3
"""Compare official violation outcomes against RAND on matched seeds."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", default="RAND")
    return parser.parse_args()


def exact_mcnemar_p(first_only: int, second_only: int) -> float:
    """Return the exact two-sided McNemar/binomial p-value."""
    discordant = first_only + second_only
    if discordant == 0:
        return 1.0
    tail = sum(
        math.comb(discordant, index)
        for index in range(min(first_only, second_only) + 1)
    ) / 2**discordant
    return min(1.0, 2 * tail)


def holm_adjust(p_values: list[float]) -> list[float]:
    """Return Holm family-wise-error adjusted p-values."""
    order = sorted(range(len(p_values)), key=p_values.__getitem__)
    adjusted = [0.0] * len(p_values)
    running_maximum = 0.0
    count = len(p_values)
    for rank, index in enumerate(order):
        candidate = min(1.0, (count - rank) * p_values[index])
        running_maximum = max(running_maximum, candidate)
        adjusted[index] = running_maximum
    return adjusted


def main() -> int:
    args = parse_args()
    with args.runs.open(newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise ValueError("run table is empty")

    outcomes: dict[tuple[str, str], bool] = {}
    algorithms: list[str] = []
    for row in rows:
        algorithm = row["Algorithm"]
        seed = row["Seed"]
        key = (algorithm, seed)
        if key in outcomes:
            raise ValueError(f"duplicate algorithm/seed row: {key}")
        if not all(
            row[field] == "True"
            for field in ("FalsifyRunPass", "InputPass", "OfficialReplayPass")
        ) or row["MatlabReturnCode"] != "0":
            raise ValueError(f"invalid pipeline row: {key}")
        outcomes[key] = row["OfficialClassification"] == "VIOLATED"
        if algorithm not in algorithms:
            algorithms.append(algorithm)

    if args.baseline not in algorithms:
        raise ValueError(f"baseline is absent: {args.baseline}")
    baseline_seeds = {
        seed for algorithm, seed in outcomes if algorithm == args.baseline
    }

    comparisons: list[dict[str, object]] = []
    for algorithm in algorithms:
        if algorithm == args.baseline:
            continue
        algorithm_seeds = {
            seed for candidate, seed in outcomes if candidate == algorithm
        }
        if algorithm_seeds != baseline_seeds:
            raise ValueError(
                f"seed set differs for {algorithm} and {args.baseline}"
            )
        both = first_only = baseline_only = neither = 0
        for seed in sorted(baseline_seeds, key=int):
            first = outcomes[algorithm, seed]
            baseline = outcomes[args.baseline, seed]
            if first and baseline:
                both += 1
            elif first:
                first_only += 1
            elif baseline:
                baseline_only += 1
            else:
                neither += 1
        comparisons.append(
            {
                "Algorithm": algorithm,
                "Baseline": args.baseline,
                "MatchedSeeds": len(baseline_seeds),
                "BothViolated": both,
                "AlgorithmOnlyViolated": first_only,
                "BaselineOnlyViolated": baseline_only,
                "NeitherViolated": neither,
                "ExactMcNemarP": exact_mcnemar_p(
                    first_only, baseline_only
                ),
            }
        )

    adjusted = holm_adjust(
        [float(row["ExactMcNemarP"]) for row in comparisons]
    )
    for row, adjusted_p in zip(comparisons, adjusted):
        row["HolmAdjustedP"] = adjusted_p

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(comparisons[0]),
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(comparisons)
    print(f"Pairwise comparisons: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
