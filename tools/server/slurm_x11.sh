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
# Ordered, bounded allocation attempts. Never timeout a running EDA process.
read -r -a task_nodes <<< "${NPU_SLURM_NODES:-${NPU_SLURM_NODE:-black}}"
task_busy_timeout=${NPU_SLURM_BUSY_TIMEOUT:-30}
if [[ ! "$task_busy_timeout" =~ ^[0-9]+$ ]] ||
   (( ${#task_busy_timeout} > 3 )) ||
   (( 10#$task_busy_timeout < 1 || 10#$task_busy_timeout > 300 )); then
    echo 'NPU_SLURM_BUSY_TIMEOUT must be 1..300 seconds' >&2; exit 2
fi
if (( ${#task_nodes[@]} < 1 || ${#task_nodes[@]} > 3 )); then
    echo 'Choose one to three nodes, without duplicates' >&2; exit 2
fi
task_seen=' '
for task_node in "${task_nodes[@]}"; do
    case "$task_node" in black|gray|white) ;; *) echo 'Choose black, gray or white' >&2; exit 2 ;; esac
    if [[ "$task_seen" == *" $task_node "* ]]; then
        echo 'Duplicate node in NPU_SLURM_NODES' >&2; exit 2
    fi
    task_seen+="$task_node "
done
printf 'NPU_X11_VALIDATED display=%s\n' "$DISPLAY"
for task_node in "${task_nodes[@]}"; do
    printf 'NPU_ALLOCATION_ATTEMPT node=%s busy_timeout=%ss\n' "$task_node" "$task_busy_timeout"
    # Slurm uses this distinct exit code only when --immediate cannot allocate.
    if SLURM_EXIT_IMMEDIATE=75 srun --pty --x11 --nodelist="$task_node" -c 2 \
        --time=05:00:00 --immediate="$task_busy_timeout" \
        bash -l "$task_root/tools/server/run.sh" "$@"; then
        exit 0
    else
        task_status=$?
    fi
    if (( task_status != 75 )); then
        echo "NPU_LAUNCH_FAILED node=$task_node exit=$task_status; no EDA retry" >&2
        exit "$task_status"
    fi
    echo "NPU_NODE_BUSY node=$task_node; trying next configured node"
done
echo 'NPU_ALL_NODES_BUSY: allocation attempts exhausted; no EDA started' >&2
exit 75
