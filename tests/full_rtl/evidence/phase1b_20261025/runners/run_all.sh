#!/bin/bash
# usage: run_all.sh <parallel> <variants...>
root=$HOME/npu_phase1b_20261025
P=$1; shift
tops="tb_quartus_memory tb_llm_math tb_llm_ram tb_llm_protocol tb_llm_selection tb_llm_operators tb_llm_graph tb_llm_linear_stream"
{ for s in xcelium questa; do for v in "$@"; do for t in $tops; do echo "$s $v $t"; done
    [ "$v" = cand ] && echo "$s $v tb_llm_head_stream"; done; done; } |
  xargs -P "$P" -L 1 bash "$root/run_one.sh" > "$root/summary.txt" 2>&1
echo ALL_DONE >> "$root/summary.txt"
