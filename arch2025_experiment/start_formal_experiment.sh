#!/usr/bin/env bash

set -euo pipefail

: "${FALSIFY_ARCH2025_EXPERIMENT_ROOT:?Set FALSIFY_ARCH2025_EXPERIMENT_ROOT}"
: "${FALSIFY_ARCH2025_EXPECTED_SHA:?Set FALSIFY_ARCH2025_EXPECTED_SHA}"

ROOT=$FALSIFY_ARCH2025_EXPERIMENT_ROOT
FALSIFY_ROOT="$ROOT/src/Falsify"
OFFICIAL_REPO="$ROOT/src/ARCH-COMP"
FALBENCH_ROOT="$ROOT/src/FalBenchGen"
PYTHON="$ROOT/env/falsify-py39/bin/python"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLS="$SCRIPT_DIR/formal_tools.py"
MANIFEST_ROOT="$ROOT/manifests/formal"
MANIFEST="$MANIFEST_ROOT/trials.csv"
RUN_ROOT="$ROOT/runs/formal"
LOG_ROOT="$ROOT/logs/formal"
BATCH_LOG_ROOT="$ROOT/logs/formal-batches"
START_LOG_ROOT="$ROOT/logs/formal-start"

OFFICIAL_SHA=5e8f72b8d5f30be002f40ae5df4a8e04d7f64e3c
FALBENCH_SHA=a6dc83d64e329a6183f910c512fc52ab27a13553

[[ $(git -C "$FALSIFY_ROOT" rev-parse HEAD) == "$FALSIFY_ARCH2025_EXPECTED_SHA" ]]
[[ $(git -C "$OFFICIAL_REPO" rev-parse HEAD) == "$OFFICIAL_SHA" ]]
[[ $(git -C "$FALBENCH_ROOT" rev-parse HEAD) == "$FALBENCH_SHA" ]]
[[ -z $(git -C "$FALSIFY_ROOT" status --porcelain=v1 --untracked-files=all) ]]
[[ -z $(git -C "$OFFICIAL_REPO" status --porcelain=v1 --untracked-files=all) ]]
[[ -z $(git -C "$FALBENCH_ROOT" status --porcelain=v1 --untracked-files=all) ]]

command -v tmux >/dev/null
mkdir -p "$MANIFEST_ROOT" "$RUN_ROOT" "$LOG_ROOT" "$BATCH_LOG_ROOT" "$START_LOG_ROOT"

if [[ ! -f "$MANIFEST" ]]; then
  : "${FALSIFY_ARCH2025_CATALOG:?Set FALSIFY_ARCH2025_CATALOG for the first start}"
  "$PYTHON" "$TOOLS" build-manifest \
    --catalog "$FALSIFY_ARCH2025_CATALOG" \
    --output "$MANIFEST"
  sha256sum "$FALSIFY_ARCH2025_CATALOG" > "$MANIFEST_ROOT/catalog-sha256.txt"
fi

"$PYTHON" -c \
  "import csv,sys; rows=list(csv.DictReader(open(sys.argv[1], newline='', encoding='utf-8-sig'))); assert len(rows)==1960; assert len({r['TrialID'] for r in rows})==1960" \
  "$MANIFEST"

if tmux has-session -t falsify-formal-s01-sb 2>/dev/null; then
  echo "initial formal batch is already running" >&2
  exit 20
fi
if tmux has-session -t falsify-formal-supervisor 2>/dev/null; then
  echo "formal supervisor is already running" >&2
  exit 21
fi

launch_id=$(date -u +%Y%m%dT%H%M%SZ)
launch_manifest="$MANIFEST_ROOT/launch-$launch_id"
mkdir -p "$launch_manifest" "$BATCH_LOG_ROOT/s01_sb"
printf '%s\n' "$FALSIFY_ARCH2025_EXPECTED_SHA" > "$launch_manifest/falsify-sha.txt"
printf '%s\n' "$OFFICIAL_SHA" > "$launch_manifest/official-sha.txt"
printf '%s\n' "$FALBENCH_SHA" > "$launch_manifest/falbench-sha.txt"
sha256sum "$MANIFEST" > "$launch_manifest/trials-sha256.txt"
printf '%s\n' "$(date --iso-8601=seconds)" > "$launch_manifest/started_at.txt"

batch_log="$BATCH_LOG_ROOT/s01_sb/start-$launch_id.log"
supervisor_log="$START_LOG_ROOT/supervisor-$launch_id.log"

tmux new-session -d -s falsify-formal-s01-sb \
  "env FALSIFY_ARCH2025_EXPERIMENT_ROOT='$ROOT' FALSIFY_ARCH2025_EXPECTED_SHA='$FALSIFY_ARCH2025_EXPECTED_SHA' bash '$SCRIPT_DIR/run_formal_batch.sh' s01_sb > '$batch_log' 2>&1"

tmux new-session -d -s falsify-formal-supervisor \
  "env FALSIFY_ARCH2025_EXPERIMENT_ROOT='$ROOT' FALSIFY_ARCH2025_EXPECTED_SHA='$FALSIFY_ARCH2025_EXPECTED_SHA' bash '$SCRIPT_DIR/run_formal_supervisor.sh' > '$supervisor_log' 2>&1"

printf '%s\n' "$batch_log" > "$launch_manifest/initial-batch-log.txt"
printf '%s\n' "$supervisor_log" > "$launch_manifest/supervisor-log.txt"
tmux list-sessions > "$launch_manifest/tmux-after-start.txt"

echo "formal experiment started"
echo "manifest: $MANIFEST"
echo "initial batch log: $batch_log"
echo "supervisor log: $supervisor_log"
