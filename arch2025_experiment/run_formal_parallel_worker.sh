#!/usr/bin/env bash

set -uo pipefail

if [[ $# -ne 2 ]]; then
  printf 'usage: %s WORKER_INDEX WORKER_COUNT\n' "$0" >&2
  exit 2
fi

WORKER_INDEX=$1
WORKER_COUNT=$2
: "${FALSIFY_ARCH2025_EXPERIMENT_ROOT:?Set FALSIFY_ARCH2025_EXPERIMENT_ROOT}"
: "${FALSIFY_ARCH2025_EXPECTED_SHA:?Set FALSIFY_ARCH2025_EXPECTED_SHA}"
: "${FALSIFY_ARCH2025_LAUNCH_ID:?Set FALSIFY_ARCH2025_LAUNCH_ID}"
: "${FALSIFY_ARCH2025_CPU_LIST:?Set FALSIFY_ARCH2025_CPU_LIST}"
: "${FALSIFY_ARCH2025_THREADS_PER_WORKER:?Set FALSIFY_ARCH2025_THREADS_PER_WORKER}"

if [[ ! "$WORKER_INDEX" =~ ^[1-9][0-9]*$ || ! "$WORKER_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  printf 'worker index and count must be positive integers\n' >&2
  exit 3
fi
if (( WORKER_INDEX > WORKER_COUNT )); then
  printf 'worker index %d exceeds worker count %d\n' "$WORKER_INDEX" "$WORKER_COUNT" >&2
  exit 4
fi

ROOT=$FALSIFY_ARCH2025_EXPERIMENT_ROOT
RUN_NAMESPACE=${FALSIFY_ARCH2025_RUN_NAMESPACE:-formal}
FORMAL_MANIFEST=${FALSIFY_ARCH2025_MANIFEST:-$ROOT/manifests/formal/trials.csv}
WORKER_ID=$(printf 'w%02d' "$WORKER_INDEX")
PYTHON="$ROOT/env/falsify-py39/bin/python"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLS="$SCRIPT_DIR/formal_tools.py"
BATCH_RUNNER="$SCRIPT_DIR/run_formal_batch.sh"
RUN_ROOT="$ROOT/runs/$RUN_NAMESPACE"
LOCK_ROOT="$ROOT/manifests/$RUN_NAMESPACE/locks"
WORKER_ROOT="$ROOT/manifests/$RUN_NAMESPACE/workers/$FALSIFY_ARCH2025_LAUNCH_ID/$WORKER_ID"
BATCH_LOG_ROOT="$ROOT/logs/$RUN_NAMESPACE/workers/$FALSIFY_ARCH2025_LAUNCH_ID/$WORKER_ID"

mkdir -p "$LOCK_ROOT" "$WORKER_ROOT" "$BATCH_LOG_ROOT"
trap 'status=$?; printf "%d\n" "$status" > "$WORKER_ROOT/exit-code.txt"' EXIT
printf '%s\n' "$(date --iso-8601=seconds)" > "$WORKER_ROOT/started-at.txt"
printf '%s\n' "$WORKER_INDEX" > "$WORKER_ROOT/worker-index.txt"
printf '%s\n' "$WORKER_COUNT" > "$WORKER_ROOT/worker-count.txt"
printf '%s\n' "$FALSIFY_ARCH2025_CPU_LIST" > "$WORKER_ROOT/cpu-list.txt"
printf '%s\n' "$FALSIFY_ARCH2025_THREADS_PER_WORKER" > "$WORKER_ROOT/threads-per-worker.txt"

mapfile -t batches < <(
  "$PYTHON" -c \
    "import csv,sys; seen=set(); rows=csv.DictReader(open(sys.argv[1],newline='',encoding='utf-8-sig')); [print(r['BatchID']) for r in rows if not (r['BatchID'] in seen or seen.add(r['BatchID']))]" \
    "$FORMAL_MANIFEST"
)

if (( ${#batches[@]} == 0 )); then
  printf 'manifest has no batches: %s\n' "$FORMAL_MANIFEST" >&2
  exit 5
fi

failure_count=0
executed_batches=0
skipped_complete=0
skipped_locked=0

for ((offset = 0; offset < ${#batches[@]}; offset++)); do
  position=$(((offset + WORKER_INDEX - 1) % ${#batches[@]}))
  batch_id=${batches[$position]}
  lock_file="$LOCK_ROOT/$batch_id.lock"
  exec {lock_fd}>"$lock_file"
  if ! flock -n "$lock_fd"; then
    skipped_locked=$((skipped_locked + 1))
    exec {lock_fd}>&-
    continue
  fi

  pending_file="$WORKER_ROOT/$batch_id-pending.tsv"
  "$PYTHON" "$TOOLS" pending \
    --manifest "$FORMAL_MANIFEST" \
    --batch "$batch_id" \
    --run-root "$RUN_ROOT" \
    > "$pending_file"
  pending_exit=$?
  if [[ $pending_exit -ne 0 ]]; then
    printf '%d\n' "$pending_exit" > "$WORKER_ROOT/$batch_id-pending-exit-code.txt"
    failure_count=$((failure_count + 1))
    flock -u "$lock_fd"
    exec {lock_fd}>&-
    break
  fi
  if [[ ! -s "$pending_file" ]]; then
    skipped_complete=$((skipped_complete + 1))
    flock -u "$lock_fd"
    exec {lock_fd}>&-
    continue
  fi

  batch_log="$BATCH_LOG_ROOT/$batch_id.log"
  printf '%s running %s\n' "$(date --iso-8601=seconds)" "$batch_id" > "$WORKER_ROOT/status.txt"
  env \
    FALSIFY_ARCH2025_EXPERIMENT_ROOT="$ROOT" \
    FALSIFY_ARCH2025_EXPECTED_SHA="$FALSIFY_ARCH2025_EXPECTED_SHA" \
    FALSIFY_ARCH2025_RUN_NAMESPACE="$RUN_NAMESPACE" \
    FALSIFY_ARCH2025_MANIFEST="$FORMAL_MANIFEST" \
    FALSIFY_ARCH2025_WORKER_ID="$WORKER_ID" \
    FALSIFY_ARCH2025_CPU_LIST="$FALSIFY_ARCH2025_CPU_LIST" \
    FALSIFY_ARCH2025_THREADS_PER_WORKER="$FALSIFY_ARCH2025_THREADS_PER_WORKER" \
    FALSIFY_ARCH2025_DEFER_AGGREGATE=1 \
    bash "$BATCH_RUNNER" "$batch_id" > "$batch_log" 2>&1
  batch_exit=$?
  executed_batches=$((executed_batches + 1))
  printf '%d\n' "$batch_exit" > "$WORKER_ROOT/$batch_id-exit-code.txt"
  flock -u "$lock_fd"
  exec {lock_fd}>&-

  if [[ $batch_exit -ne 0 ]]; then
    failure_count=$((failure_count + 1))
    printf '%s batch %s failed with code %d\n' \
      "$(date --iso-8601=seconds)" "$batch_id" "$batch_exit" > "$WORKER_ROOT/status.txt"
    break
  fi
done

printf '%d\n' "$executed_batches" > "$WORKER_ROOT/executed-batches.txt"
printf '%d\n' "$skipped_complete" > "$WORKER_ROOT/skipped-complete.txt"
printf '%d\n' "$skipped_locked" > "$WORKER_ROOT/skipped-locked.txt"
printf '%d\n' "$failure_count" > "$WORKER_ROOT/failure-count.txt"
printf '%s\n' "$(date --iso-8601=seconds)" > "$WORKER_ROOT/ended-at.txt"

if [[ $failure_count -ne 0 ]]; then
  exit 1
fi
printf '%s all assigned work finished\n' "$(date --iso-8601=seconds)" > "$WORKER_ROOT/status.txt"
exit 0
