#!/bin/bash -l
# Invoke from the repository root, inside an approved allocation.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
: "${SLURM_JOB_ID:?Run inside an approved Slurm compute allocation}"
: "${DISPLAY:?X11 must be available; keep --x11 on srun}"
xdpyinfo >/dev/null 2>&1 || { echo 'Compute X11 connection failed' >&2; exit 1; }
printf 'NPU_COMPUTE_JOB_ID=%s NODE=%s DISPLAY=%s\n' "$SLURM_JOB_ID" "$(hostname)" "$DISPLAY"
if ! type module >/dev/null 2>&1; then
    echo 'module is unavailable; initialize the lab environment in your allocated shell.' >&2
    exit 1
fi
# Modules confirmed on black during the X11 probe; keep versions in flow.json.
stage=${1:-test}
if [[ $# -gt 0 ]]; then shift; fi
case "$stage" in
    test|application|legacy|all)
        sim_module=$(python3 -c 'import json; print(json.load(open("tools/server/flow.json"))["modules"]["simulation"] or "")')
        [[ -n "$sim_module" ]] || { echo 'Set modules.simulation in flow.json' >&2; exit 1; }
        module load "$sim_module"
        ;;
esac
case "$stage" in
    syn|all)
        syn_module=$(python3 -c 'import json; print(json.load(open("tools/server/flow.json"))["modules"]["synthesis"] or "")')
        [[ -n "$syn_module" ]] || { echo 'Discover Genus with module avail, then set modules.synthesis in flow.json' >&2; exit 1; }
        module load "$syn_module"
        ;;
esac
exec python3 tools/server/run_flow.py --stage "$stage" "$@"
