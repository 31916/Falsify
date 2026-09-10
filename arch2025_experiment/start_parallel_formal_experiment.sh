#!/usr/bin/env bash

set -euo pipefail

: "${FALSIFY_ARCH2025_EXPERIMENT_ROOT:?Set FALSIFY_ARCH2025_EXPERIMENT_ROOT}"
: "${FALSIFY_ARCH2025_EXPECTED_SHA:?Set FALSIFY_ARCH2025_EXPECTED_SHA}"

ROOT=$FALSIFY_ARCH2025_EXPERIMENT_ROOT
RUN_NAMESPACE=${FALSIFY_ARCH2025_RUN_NAMESPACE:-formal}
WORKER_COUNT=${FALSIFY_ARCH2025_WORKER_COUNT:-8}
CPUS_PER_WORKER=${FALSIFY_ARCH2025_CPUS_PER_WORKER:-4}
EXPECTED_TRIALS=${FALSIFY_ARCH2025_EXPECTED_TRIALS:-1960}
EXPECTED_MAX_EVALUATIONS=${FALSIFY_ARCH2025_EXPECTED_MAX_EVALUATIONS:-1500}
FORMAL_MANIFEST=${FALSIFY_ARCH2025_MANIFEST:-$ROOT/manifests/formal/trials.csv}
FALSIFY_ROOT="$ROOT/src/Falsify"
OFFICIAL_REPO="$ROOT/src/ARCH-COMP"
FALBENCH_ROOT="$ROOT/src/FalBenchGen"
PYTHON="$ROOT/env/falsify-py39/bin/python"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKER_SCRIPT="$SCRIPT_DIR/run_formal_parallel_worker.sh"
MONITOR_SCRIPT="$SCRIPT_DIR/run_formal_parallel_monitor.sh"
SESSION_PREFIX="falsify-$RUN_NAMESPACE"
MANIFEST_ROOT="$ROOT/manifests/$RUN_NAMESPACE"
START_LOG_ROOT="$ROOT/logs/$RUN_NAMESPACE/start"

OFFICIAL_SHA=5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c
FALBENCH_SHA=a6dc83d64e329a6183f910c512fc52ab27a13553

if [[ ! "$RUN_NAMESPACE" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  printf 'invalid FALSIFY_ARCH2025_RUN_NAMESPACE: %s\n' "$RUN_NAMESPACE" >&2
  exit 3
fi
for value in "$WORKER_COUNT" "$CPUS_PER_WORKER" "$EXPECTED_TRIALS" "$EXPECTED_MAX_EVALUATIONS"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || exit 4
done

online_cpus=$(getconf _NPROCESSORS_ONLN)
required_cpus=$((WORKER_COUNT * CPUS_PER_WORKER))
if (( required_cpus > online_cpus )); then
  printf 'requested %d CPUs but only %d are online\n' "$required_cpus" "$online_cpus" >&2
  exit 5
fi

available_kib=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
required_memory_kib=$(((WORKER_COUNT * 4 + 8) * 1024 * 1024))
if (( available_kib < required_memory_kib )); then
  printf 'available memory is below the %d-worker safety threshold\n' "$WORKER_COUNT" >&2
  exit 6
fi
available_disk_kib=$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')
if (( available_disk_kib < 104857600 )); then
  printf 'available disk is below 100 GiB\n' >&2
  exit 7
fi

[[ $(git -C "$FALSIFY_ROOT" rev-parse HEAD) == "$FALSIFY_ARCH2025_EXPECTED_SHA" ]]
[[ $(git -C "$OFFICIAL_REPO" rev-parse HEAD) == "$OFFICIAL_SHA" ]]
[[ $(git -C "$FALBENCH_ROOT" rev-parse HEAD) == "$FALBENCH_SHA" ]]
[[ -z $(git -C "$FALSIFY_ROOT" status --porcelain=v1 --untracked-files=all) ]]
[[ -z $(git -C "$OFFICIAL_REPO" status --porcelain=v1 --untracked-files=all) ]]
[[ -z $(git -C "$FALBENCH_ROOT" status --porcelain=v1 --untracked-files=all) ]]
command -v tmux >/dev/null
command -v flock >/dev/null

"$PYTHON" -c \
  "import csv,sys; rows=list(csv.DictReader(open(sys.argv[1],newline='',encoding='utf-8-sig'))); expected=int(sys.argv[2]); max_eval=int(sys.argv[3]); assert len(rows)==expected, (len(rows),expected); assert len({r['TrialID'] for r in rows})==expected; assert all(int(r['MaxEvaluations'])==max_eval for r in rows); assert len({r['BatchID'] for r in rows})>=int(sys.argv[4])" \
  "$FORMAL_MANIFEST" "$EXPECTED_TRIALS" "$EXPECTED_MAX_EVALUATIONS" "$WORKER_COUNT"

if tmux list-sessions -F '#S' 2>/dev/null | grep -Eq "^${SESSION_PREFIX}-(w[0-9]+|monitor)$"; then
  printf 'parallel run sessions already exist for namespace %s\n' "$RUN_NAMESPACE" >&2
  exit 20
fi

launch_id=$(date -u +%Y%m%dT%H%M%SZ)
launch_root="$MANIFEST_ROOT/launch-$launch_id"
mkdir -p "$launch_root" "$START_LOG_ROOT"
printf '%s\n' "$launch_id" > "$launch_root/launch-id.txt"
printf '%s\n' "$WORKER_COUNT" > "$launch_root/worker-count.txt"
printf '%s\n' "$CPUS_PER_WORKER" > "$launch_root/cpus-per-worker.txt"
printf '%s\n' "$RUN_NAMESPACE" > "$launch_root/run-namespace.txt"
printf '%s\n' "$FALSIFY_ARCH2025_EXPECTED_SHA" > "$launch_root/falsify-sha.txt"
printf '%s\n' "$OFFICIAL_SHA" > "$launch_root/official-sha.txt"
printf '%s\n' "$FALBENCH_SHA" > "$launch_root/falbench-sha.txt"
sha256sum "$FORMAL_MANIFEST" > "$launch_root/trials-sha256.txt"
printf '%s\n' "$(date --iso-8601=seconds)" > "$launch_root/started-at.txt"
printf 'Worker,CPUList,Session,Log\n' > "$launch_root/worker-cpu-map.csv"

for ((worker = 1; worker <= WORKER_COUNT; worker++)); do
  worker_id=$(printf 'w%02d' "$worker")
  cpu_start=$(((worker - 1) * CPUS_PER_WORKER))
  cpu_end=$((cpu_start + CPUS_PER_WORKER - 1))
  cpu_list="$cpu_start-$cpu_end"
  session="$SESSION_PREFIX-$worker_id"
  log="$START_LOG_ROOT/$launch_id-$worker_id.log"
  printf '%s,%s,%s,%s\n' "$worker_id" "$cpu_list" "$session" "$log" >> "$launch_root/worker-cpu-map.csv"
  printf -v command '%q ' env \
    FALSIFY_ARCH2025_EXPERIMENT_ROOT="$ROOT" \
    FALSIFY_ARCH2025_EXPECTED_SHA="$FALSIFY_ARCH2025_EXPECTED_SHA" \
    FALSIFY_ARCH2025_RUN_NAMESPACE="$RUN_NAMESPACE" \
    FALSIFY_ARCH2025_MANIFEST="$FORMAL_MANIFEST" \
    FALSIFY_ARCH2025_EXPECTED_TRIALS="$EXPECTED_TRIALS" \
    FALSIFY_ARCH2025_LAUNCH_ID="$launch_id" \
    FALSIFY_ARCH2025_CPU_LIST="$cpu_list" \
    FALSIFY_ARCH2025_THREADS_PER_WORKER="$CPUS_PER_WORKER" \
    bash "$WORKER_SCRIPT" "$worker" "$WORKER_COUNT"
  command+="> $(printf '%q' "$log") 2>&1"
  tmux new-session -d -s "$session" "$command"
done

monitor_session="$SESSION_PREFIX-monitor"
monitor_log="$START_LOG_ROOT/$launch_id-monitor.log"
printf -v monitor_command '%q ' env \
  FALSIFY_ARCH2025_EXPERIMENT_ROOT="$ROOT" \
  FALSIFY_ARCH2025_RUN_NAMESPACE="$RUN_NAMESPACE" \
  FALSIFY_ARCH2025_MANIFEST="$FORMAL_MANIFEST" \
  FALSIFY_ARCH2025_EXPECTED_TRIALS="$EXPECTED_TRIALS" \
  FALSIFY_ARCH2025_LAUNCH_ID="$launch_id" \
  bash "$MONITOR_SCRIPT" "$WORKER_COUNT"
monitor_command+="> $(printf '%q' "$monitor_log") 2>&1"
tmux new-session -d -s "$monitor_session" "$monitor_command"

printf '%s\n' "$monitor_log" > "$launch_root/monitor-log.txt"
tmux list-sessions > "$launch_root/tmux-after-start.txt"
printf 'parallel experiment started with %d workers\n' "$WORKER_COUNT"
printf 'namespace: %s\n' "$RUN_NAMESPACE"
printf 'launch: %s\n' "$launch_id"
printf 'manifest: %s\n' "$FORMAL_MANIFEST"
