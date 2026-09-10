#!/usr/bin/env bash

set -uo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s WORKER_COUNT\n' "$0" >&2
  exit 2
fi

WORKER_COUNT=$1
: "${FALSIFY_ARCH2025_EXPERIMENT_ROOT:?Set FALSIFY_ARCH2025_EXPERIMENT_ROOT}"
: "${FALSIFY_ARCH2025_LAUNCH_ID:?Set FALSIFY_ARCH2025_LAUNCH_ID}"

ROOT=$FALSIFY_ARCH2025_EXPERIMENT_ROOT
RUN_NAMESPACE=${FALSIFY_ARCH2025_RUN_NAMESPACE:-formal}
FORMAL_MANIFEST=${FALSIFY_ARCH2025_MANIFEST:-$ROOT/manifests/formal/trials.csv}
EXPECTED_TRIALS=${FALSIFY_ARCH2025_EXPECTED_TRIALS:-1960}
SESSION_PREFIX="falsify-$RUN_NAMESPACE"
PYTHON="$ROOT/env/falsify-py39/bin/python"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLS="$SCRIPT_DIR/formal_tools.py"
RUN_ROOT="$ROOT/runs/$RUN_NAMESPACE"
TRIAL_MANIFEST_ROOT="$ROOT/manifests/$RUN_NAMESPACE/trials"
SUMMARY_ROOT="$ROOT/summaries/$RUN_NAMESPACE"
LAUNCH_ROOT="$ROOT/manifests/$RUN_NAMESPACE/launch-$FALSIFY_ARCH2025_LAUNCH_ID"
MONITOR_ROOT="$LAUNCH_ROOT/monitor"

mkdir -p "$MONITOR_ROOT" "$SUMMARY_ROOT"
trap 'status=$?; printf "%d\n" "$status" > "$MONITOR_ROOT/exit-code.txt"' EXIT
printf '%s\n' "$(date --iso-8601=seconds)" > "$MONITOR_ROOT/started-at.txt"

while true; do
  active=0
  for ((worker = 1; worker <= WORKER_COUNT; worker++)); do
    session=$(printf '%s-w%02d' "$SESSION_PREFIX" "$worker")
    if tmux has-session -t "$session" 2>/dev/null; then
      active=$((active + 1))
    fi
  done
  printf '%s active workers: %d\n' "$(date --iso-8601=seconds)" "$active" > "$MONITOR_ROOT/status.txt"
  if [[ $active -eq 0 ]]; then
    break
  fi
  sleep 30
done

worker_failures=0
for ((worker = 1; worker <= WORKER_COUNT; worker++)); do
  worker_id=$(printf 'w%02d' "$worker")
  exit_file="$ROOT/manifests/$RUN_NAMESPACE/workers/$FALSIFY_ARCH2025_LAUNCH_ID/$worker_id/exit-code.txt"
  if [[ ! -f "$exit_file" || $(<"$exit_file") != 0 ]]; then
    worker_failures=$((worker_failures + 1))
  fi
done
printf '%d\n' "$worker_failures" > "$MONITOR_ROOT/worker-failures.txt"

"$PYTHON" "$TOOLS" aggregate \
  --manifest "$FORMAL_MANIFEST" \
  --run-root "$RUN_ROOT" \
  --manifest-root "$TRIAL_MANIFEST_ROOT" \
  --output "$SUMMARY_ROOT" \
  > "$MONITOR_ROOT/aggregate.log" 2>&1
aggregate_exit=$?
printf '%d\n' "$aggregate_exit" > "$MONITOR_ROOT/aggregate-exit-code.txt"

"$PYTHON" -c \
  "import csv,sys; rows=list(csv.DictReader(open(sys.argv[1],newline='',encoding='utf-8-sig'))); expected=int(sys.argv[2]); assert len(rows)==expected, (len(rows), expected); assert all(str(r.get('OverallPass','')).lower() in {'1','true','yes'} for r in rows)" \
  "$SUMMARY_ROOT/all_trials.csv" "$EXPECTED_TRIALS"
validation_exit=$?
printf '%d\n' "$validation_exit" > "$MONITOR_ROOT/final-validation-exit-code.txt"
printf '%s\n' "$(date --iso-8601=seconds)" > "$MONITOR_ROOT/ended-at.txt"

if [[ $worker_failures -ne 0 || $aggregate_exit -ne 0 || $validation_exit -ne 0 ]]; then
  printf '%s parallel run incomplete or failed\n' "$(date --iso-8601=seconds)" > "$MONITOR_ROOT/status.txt"
  exit 1
fi
printf '%s parallel run completed successfully\n' "$(date --iso-8601=seconds)" > "$MONITOR_ROOT/status.txt"
exit 0
