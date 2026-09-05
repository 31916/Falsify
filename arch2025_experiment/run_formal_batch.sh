#!/usr/bin/env bash

set -uo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s BATCH_ID\n' "$0" >&2
  exit 2
fi

BATCH_ID=$1
: "${FALSIFY_ARCH2025_EXPERIMENT_ROOT:?Set FALSIFY_ARCH2025_EXPERIMENT_ROOT}"
: "${FALSIFY_ARCH2025_EXPECTED_SHA:?Set FALSIFY_ARCH2025_EXPECTED_SHA}"
ROOT=$FALSIFY_ARCH2025_EXPERIMENT_ROOT
FALSIFY_ROOT="$ROOT/src/Falsify"
OFFICIAL_ROOT="$ROOT/src/ARCH-COMP/models/FALS"
OFFICIAL_REPO="$ROOT/src/ARCH-COMP"
FALBENCH_ROOT="$ROOT/src/FalBenchGen"
PYTHON="$ROOT/env/falsify-py39/bin/python"
MATLAB=${FALSIFY_ARCH2025_MATLAB_BIN:-/usr/local/MATLAB/R2026a/bin/matlab}
TASKSET=${FALSIFY_ARCH2025_TASKSET_BIN:-/usr/bin/taskset}
CPU_LIST=${FALSIFY_ARCH2025_CPU_LIST:-0-3}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLS="$SCRIPT_DIR/formal_tools.py"
MEX_DIR="$ROOT/build/mex"
CACHE_DIR="$ROOT/build/simulink-cache"
CODEGEN_DIR="$ROOT/build/simulink-codegen"
FORMAL_MANIFEST="$ROOT/manifests/formal/trials.csv"
RUN_ROOT="$ROOT/runs/formal"
LOG_ROOT="$ROOT/logs/formal"
TRIAL_MANIFEST_ROOT="$ROOT/manifests/formal/trials"
SUMMARY_ROOT="$ROOT/summaries/formal"
BATCH_MANIFEST_ROOT="$ROOT/manifests/formal/batches/$BATCH_ID"

mkdir -p "$RUN_ROOT" "$LOG_ROOT" "$TRIAL_MANIFEST_ROOT" "$SUMMARY_ROOT" "$BATCH_MANIFEST_ROOT" "$CACHE_DIR" "$CODEGEN_DIR"

invocation=$(date -u +%Y%m%dT%H%M%SZ)
invocation_root="$BATCH_MANIFEST_ROOT/$invocation"
mkdir -p "$invocation_root"
printf '%s\n' "$BATCH_ID" > "$invocation_root/batch-id.txt"
printf '%s\n' "$(date --iso-8601=seconds)" > "$invocation_root/started_at.txt"

git -C "$FALSIFY_ROOT" rev-parse HEAD > "$invocation_root/falsify-head-before.txt"
git -C "$FALSIFY_ROOT" status --porcelain=v1 --untracked-files=all > "$invocation_root/falsify-status-before.txt"
git -C "$OFFICIAL_REPO" rev-parse HEAD > "$invocation_root/official-head-before.txt"
git -C "$OFFICIAL_REPO" status --porcelain=v1 --untracked-files=all > "$invocation_root/official-status-before.txt"
git -C "$FALBENCH_ROOT" rev-parse HEAD > "$invocation_root/falbench-head-before.txt"
git -C "$FALBENCH_ROOT" status --porcelain=v1 --untracked-files=all > "$invocation_root/falbench-status-before.txt"

if [[ $(git -C "$FALSIFY_ROOT" rev-parse HEAD) != "$FALSIFY_ARCH2025_EXPECTED_SHA" ]]; then exit 10; fi
if [[ $(git -C "$OFFICIAL_REPO" rev-parse HEAD) != 5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c ]]; then exit 11; fi
if [[ $(git -C "$FALBENCH_ROOT" rev-parse HEAD) != a6dc83d64e329a6183f910c512fc52ab27a13553 ]]; then exit 12; fi
if [[ -s "$invocation_root/falsify-status-before.txt" || -s "$invocation_root/official-status-before.txt" || -s "$invocation_root/falbench-status-before.txt" ]]; then exit 13; fi

pending_file="$invocation_root/pending.tsv"
"$PYTHON" "$TOOLS" pending --manifest "$FORMAL_MANIFEST" --batch "$BATCH_ID" --run-root "$RUN_ROOT" > "$pending_file"
pending_exit=$?
if [[ $pending_exit -ne 0 ]]; then
  printf '%d\n' "$pending_exit" > "$invocation_root/pending-command-exit-code.txt"
  exit 20
fi

failure_count=0
executed_count=0
skipped_count=0

while IFS=$'\t' read -r sequence batch_id seed_index seed trial_id case_id model requirement instance algorithm max_evaluations; do
  [[ -n "$trial_id" ]] || continue
  trial_run="$RUN_ROOT/$trial_id"
  trial_log="$LOG_ROOT/$trial_id"
  trial_manifest="$TRIAL_MANIFEST_ROOT/$trial_id"
  mkdir -p "$trial_run" "$trial_log" "$trial_manifest"

  if [[ -f "$trial_run/complete.json" ]]; then
    skipped_count=$((skipped_count + 1))
    continue
  fi

  attempt_number=1
  while [[ -d "$trial_manifest/attempt-$(printf '%03d' "$attempt_number")" || -d "$trial_run/attempt-$(printf '%03d' "$attempt_number")" ]]; do
    attempt_number=$((attempt_number + 1))
  done
  attempt_name="attempt-$(printf '%03d' "$attempt_number")"
  attempt_run="$trial_run/$attempt_name"
  attempt_log="$trial_log/$attempt_name"
  attempt_manifest="$trial_manifest/$attempt_name"
  mkdir -p "$attempt_run" "$attempt_log" "$attempt_manifest"

  export FALSIFY_ARCH2025_OFFICIAL_ROOT="$OFFICIAL_ROOT"
  export FALSIFY_ARCH2025_FALBENCH_ROOT="$FALBENCH_ROOT"
  export FALSIFY_ARCH2025_PYTHON="$PYTHON"
  export FALSIFY_ARCH2025_AT_DATA="$ROOT/assets/mathworks/sldemo_autotrans_data.mat"
  export FALSIFY_ARCH2025_MAX_EPISODES="$max_evaluations"
  export FALSIFY_ARCH2025_SEED_OVERRIDE="$seed"
  export FALSIFY_ARCH2025_RESUME_COMPLETED=0
  export FALSIFY_ARCH2025_REBUILD_WRAPPERS=0
  export FALSIFY_ARCH2025_CASE_FILTER="$case_id"
  export FALSIFY_ARCH2025_OUTPUT_DIR="$attempt_run/results"
  export FALSIFY_FORMAL_CPU_LIST="$CPU_LIST"
  export MATLAB_PREFDIR="$ROOT/build/matlab-prefs"
  export OMP_NUM_THREADS=4
  export OMP_THREAD_LIMIT=4
  export OPENBLAS_NUM_THREADS=4
  export MKL_NUM_THREADS=4
  export NUMEXPR_NUM_THREADS=4

  printf '%s\n' "$(date --iso-8601=seconds)" > "$attempt_manifest/started_at.txt"
  env | LC_ALL=C sort | grep -E '^(FALSIFY_ARCH2025_|FALSIFY_FORMAL_|MATLAB_PREFDIR|OMP_|OPENBLAS_|MKL_|NUMEXPR_)' > "$attempt_manifest/environment.txt"
  printf '%s\n' "$sequence,$batch_id,$seed_index,$seed,$trial_id,$case_id,$model,$requirement,$instance,$algorithm,$max_evaluations" > "$attempt_manifest/trial.csv"

  matlab_expression="Simulink.fileGenControl('set','CacheFolder','$CACHE_DIR','CodeGenFolder','$CODEGEN_DIR','createDir',true); addpath('$MEX_DIR','-begin'); cd('$FALSIFY_ROOT'); validate_arch2025_all"
  printf '%q ' /usr/bin/time -v -o "$attempt_log/time-v.txt" "$TASKSET" --cpu-list "$CPU_LIST" "$MATLAB" -logfile "$attempt_log/matlab.log" -batch "$matlab_expression" > "$attempt_manifest/command.txt"
  printf '\n' >> "$attempt_manifest/command.txt"

  /usr/bin/time -v -o "$attempt_log/time-v.txt" \
    "$TASKSET" --cpu-list "$CPU_LIST" \
    "$MATLAB" -logfile "$attempt_log/matlab.log" -batch "$matlab_expression"
  matlab_exit=$?
  executed_count=$((executed_count + 1))

  printf '%d\n' "$matlab_exit" > "$attempt_manifest/matlab-exit-code.txt"
  printf '%s\n' "$(date --iso-8601=seconds)" > "$attempt_manifest/ended_at.txt"
  grep -c '^Current iteration:' "$attempt_log/matlab.log" > "$attempt_manifest/logged-iteration-count.txt" || true
  git -C "$FALSIFY_ROOT" status --porcelain=v1 --untracked-files=all > "$attempt_manifest/falsify-status-after.txt"
  git -C "$OFFICIAL_REPO" status --porcelain=v1 --untracked-files=all > "$attempt_manifest/official-status-after.txt"
  git -C "$FALBENCH_ROOT" status --porcelain=v1 --untracked-files=all > "$attempt_manifest/falbench-status-after.txt"

  if [[ -s "$attempt_manifest/falsify-status-after.txt" || -s "$attempt_manifest/official-status-after.txt" || -s "$attempt_manifest/falbench-status-after.txt" ]]; then
    printf '%s\n' 'A protected checkout became dirty; the batch stopped.' > "$attempt_manifest/repository-dirty.txt"
    exit 99
  fi

  "$PYTHON" "$TOOLS" validate-attempt \
    --summary "$attempt_run/results/arch2025_all_summary.csv" \
    --case-id "$case_id" \
    --seed "$seed" \
    --max-evaluations "$max_evaluations" \
    --matlab-exit "$matlab_exit" \
    --trial-id "$trial_id" \
    --batch-id "$batch_id" \
    --sequence "$sequence" \
    --time-file "$attempt_log/time-v.txt" \
    --matlab-log "$attempt_log/matlab.log" \
    --attempt-status "$attempt_manifest/attempt-status.json" \
    --complete "$trial_run/complete.json"
  validation_exit=$?
  printf '%d\n' "$validation_exit" > "$attempt_manifest/result-validation-exit-code.txt"
  if [[ $validation_exit -ne 0 ]]; then
    failure_count=$((failure_count + 1))
  fi

  "$PYTHON" "$TOOLS" aggregate \
    --manifest "$FORMAL_MANIFEST" \
    --run-root "$RUN_ROOT" \
    --manifest-root "$TRIAL_MANIFEST_ROOT" \
    --output "$SUMMARY_ROOT"
done < "$pending_file"

printf '%s\n' "$(date --iso-8601=seconds)" > "$invocation_root/ended_at.txt"
printf '%d\n' "$executed_count" > "$invocation_root/executed-count.txt"
printf '%d\n' "$skipped_count" > "$invocation_root/skipped-count.txt"
printf '%d\n' "$failure_count" > "$invocation_root/failure-count.txt"

"$PYTHON" "$TOOLS" aggregate \
  --manifest "$FORMAL_MANIFEST" \
  --run-root "$RUN_ROOT" \
  --manifest-root "$TRIAL_MANIFEST_ROOT" \
  --output "$SUMMARY_ROOT"

if [[ $failure_count -ne 0 ]]; then
  exit 1
fi
exit 0
