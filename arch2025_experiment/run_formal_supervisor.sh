#!/usr/bin/env bash

set -uo pipefail

: "${FALSIFY_ARCH2025_EXPERIMENT_ROOT:?Set FALSIFY_ARCH2025_EXPERIMENT_ROOT}"
: "${FALSIFY_ARCH2025_EXPECTED_SHA:?Set FALSIFY_ARCH2025_EXPECTED_SHA}"
ROOT=$FALSIFY_ARCH2025_EXPERIMENT_ROOT
FALSIFY_ROOT="$ROOT/src/Falsify"
OFFICIAL_REPO="$ROOT/src/ARCH-COMP"
FALBENCH_ROOT="$ROOT/src/FalBenchGen"
PYTHON="$ROOT/env/falsify-py39/bin/python"
FORMAL_MANIFEST="$ROOT/manifests/formal/trials.csv"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BATCH_RUNNER="$SCRIPT_DIR/run_formal_batch.sh"
RUN_ROOT="$ROOT/runs/formal"
SUPERVISOR_ROOT="$ROOT/manifests/formal/supervisor"
BATCH_LOG_ROOT="$ROOT/logs/formal-batches"

mkdir -p "$SUPERVISOR_ROOT" "$BATCH_LOG_ROOT"
started=$(date -u +%Y%m%dT%H%M%SZ)
run_manifest="$SUPERVISOR_ROOT/$started"
mkdir -p "$run_manifest"
printf '%s\n' "$(date --iso-8601=seconds)" > "$run_manifest/started_at.txt"

batch_list="$run_manifest/batches.txt"
"$PYTHON" -c "import csv,sys; seen=set(); rows=csv.DictReader(open(sys.argv[1], newline='', encoding='utf-8-sig')); [print(r['BatchID']) for r in rows if not (r['BatchID'] in seen or seen.add(r['BatchID']))]" "$FORMAL_MANIFEST" > "$batch_list"

check_batch_complete() {
  local batch_id=$1
  "$PYTHON" -c "import csv,json,pathlib,sys; manifest,batch,root=sys.argv[1:]; rows=[r for r in csv.DictReader(open(manifest,newline='',encoding='utf-8-sig')) if r['BatchID']==batch]; done=sum((pathlib.Path(root)/r['TrialID']/'complete.json').is_file() for r in rows); print(f'{done}/{len(rows)}'); sys.exit(0 if rows and done==len(rows) else 1)" "$FORMAL_MANIFEST" "$batch_id" "$RUN_ROOT"
}

check_protected_state() {
  [[ $(git -C "$FALSIFY_ROOT" rev-parse HEAD) == "$FALSIFY_ARCH2025_EXPECTED_SHA" ]] || return 10
  [[ $(git -C "$OFFICIAL_REPO" rev-parse HEAD) == 5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c ]] || return 11
  [[ $(git -C "$FALBENCH_ROOT" rev-parse HEAD) == a6dc83d64e329a6183f910c512fc52ab27a13553 ]] || return 12
  [[ -z $(git -C "$FALSIFY_ROOT" status --porcelain=v1 --untracked-files=all) ]] || return 13
  [[ -z $(git -C "$OFFICIAL_REPO" status --porcelain=v1 --untracked-files=all) ]] || return 14
  [[ -z $(git -C "$FALBENCH_ROOT" status --porcelain=v1 --untracked-files=all) ]] || return 15
}

while tmux has-session -t falsify-formal-s01-sb 2>/dev/null; do
  printf '%s waiting for initial batch s01_sb\n' "$(date --iso-8601=seconds)" > "$run_manifest/status.txt"
  sleep 30
done

if ! check_batch_complete s01_sb > "$run_manifest/s01_sb-completion.txt"; then
  printf '%s initial batch s01_sb did not complete cleanly; supervisor stopped\n' "$(date --iso-8601=seconds)" > "$run_manifest/status.txt"
  exit 30
fi

while IFS= read -r batch_id; do
  [[ -n "$batch_id" ]] || continue
  if check_batch_complete "$batch_id" > "$run_manifest/$batch_id-before.txt"; then
    continue
  fi

  check_protected_state
  protected_exit=$?
  if [[ $protected_exit -ne 0 ]]; then
    printf '%s protected checkout check failed before %s with code %d\n' "$(date --iso-8601=seconds)" "$batch_id" "$protected_exit" > "$run_manifest/status.txt"
    exit 40
  fi

  available_kib=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
  available_disk_kib=$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')
  if (( available_kib < 16777216 )); then
    printf '%s available memory below 16 GiB before %s\n' "$(date --iso-8601=seconds)" "$batch_id" > "$run_manifest/status.txt"
    exit 41
  fi
  if (( available_disk_kib < 104857600 )); then
    printf '%s available disk below 100 GiB before %s\n' "$(date --iso-8601=seconds)" "$batch_id" > "$run_manifest/status.txt"
    exit 42
  fi

  invocation=$(date -u +%Y%m%dT%H%M%SZ)
  log_dir="$BATCH_LOG_ROOT/$batch_id"
  log_file="$log_dir/supervisor-$invocation.log"
  mkdir -p "$log_dir"
  printf '%s running %s\n' "$(date --iso-8601=seconds)" "$batch_id" > "$run_manifest/status.txt"
  bash "$BATCH_RUNNER" "$batch_id" > "$log_file" 2>&1
  batch_exit=$?
  printf '%d\n' "$batch_exit" > "$run_manifest/$batch_id-exit-code.txt"
  if [[ $batch_exit -ne 0 ]]; then
    printf '%s batch %s failed with code %d; supervisor stopped\n' "$(date --iso-8601=seconds)" "$batch_id" "$batch_exit" > "$run_manifest/status.txt"
    exit 50
  fi
  if ! check_batch_complete "$batch_id" > "$run_manifest/$batch_id-after.txt"; then
    printf '%s batch %s returned success but is incomplete; supervisor stopped\n' "$(date --iso-8601=seconds)" "$batch_id" > "$run_manifest/status.txt"
    exit 51
  fi
done < "$batch_list"

printf '%s\n' "$(date --iso-8601=seconds)" > "$run_manifest/ended_at.txt"
printf '%s all formal batches completed\n' "$(date --iso-8601=seconds)" > "$run_manifest/status.txt"
exit 0
