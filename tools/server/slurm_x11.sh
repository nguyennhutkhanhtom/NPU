#!/bin/bash -l
# Start from SSH or the account's Remote Desktop terminal; always keep --x11.
set -euo pipefail
task_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
task_base=$(realpath -m -- "$HOME/project/test_khanh")
case "$task_root" in
    "$task_base"/*) ;;
    *) echo "Run from a task bundle under $task_base" >&2; exit 2 ;;
esac
cd -- "$task_root"
if [[ -n "${SLURM_JOB_ID:-}" ]]; then
    echo 'Use run.sh within the existing allocation; do not allocate a nested job.' >&2
    exit 2
fi
command -v xauth >/dev/null
task_x11=$(python3 tools/server/resolve_x11.py)
IFS=$'\t' read -r DISPLAY XAUTHORITY <<< "$task_x11"
export DISPLAY XAUTHORITY
task_node=${NPU_SLURM_NODE:-black}
case "$task_node" in black|gray|white) ;; *) echo 'Choose black, gray or white' >&2; exit 2 ;; esac
printf 'NPU_X11_VALIDATED display=%s node=%s\n' "$DISPLAY" "$task_node"
exec srun --pty --x11 --nodelist="$task_node" -c 2 --time=05:00:00 --immediate=30 \
    bash -l "$task_root/tools/server/run.sh" "$@"
