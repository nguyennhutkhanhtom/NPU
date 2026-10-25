#!/bin/bash
# usage: run_one.sh <xcelium|questa> <base|cand> <top> [plusarg]
set -u
sim=$1; ver=$2; top=$3; plus=${4:-}
root=$HOME/npu_phase1b_20261025
d=$root/runs/${sim}_${ver}_${top}${plus:+_${plus//+/}}
rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
source /etc/profile.d/modules.sh; module use /tools/modulefiles
ALTERA_MF=/tools/Intel/intelFPGA/22.1std/quartus/eda/sim_lib/altera_mf.v
rtlsrc="$root/$ver/Verilog Source code"; tbs=$(ls "$root"/$ver/tests/full_rtl/tb_*.sv)
ln -s "$rtlsrc" rtl
ln -s "$rtlsrc" "Verilog Source code"  # tb_operators reads Verilog Source code/sigmoid_257.mem
{ echo rtl/npu_pkg.sv; echo rtl/llm_pkg.sv
  for f in rtl/*.sv; do b=$(basename "$f"); [ "$b" = npu_pkg.sv ] || [ "$b" = llm_pkg.sv ] || echo "$f"; done
  for f in $tbs; do echo "$f"; done; } > sources.f
sha256sum $(cat sources.f) > source_hashes.txt
start=$(date +%s)
if [ "$sim" = xcelium ]; then
  module load cadence/xcelium/23.03
  xrun -64bit -timescale 1ns/1ps -incdir rtl -f sources.f "$ALTERA_MF" -top "$top" -access +rw $plus -l run.log > console.log 2>&1
  rc=$?
  errs=$(grep -cE '\*(E|F),' run.log)
  warns=$(grep -cE '\*W,' run.log)
else
  module load siemens/questasim/2024.1
  { vlib work && vlog -work work "$ALTERA_MF" -l comp_mf.log &&
    vlog -sv -svinputport=var -work work +incdir+rtl -f sources.f -l comp.log &&
    vsim -c -onfinish exit -lib work -l run.log "$top" $plus -do "run -all; quit -f"; } > console.log 2>&1
  rc=$?
  errs=$(cat comp.log run.log 2>/dev/null | grep -cE '^(# )?\*\* (Fatal|Error)')
  warns=$(cat comp.log run.log 2>/dev/null | grep -cE '^(# )?\*\* Warning')
fi
end=$(date +%s)
pass=$(grep -hE '^(# )?[A-Z0-9_]+_PASS( |$)' run.log 2>/dev/null | tail -1)
echo "$sim $ver $top${plus:+ $plus} rc=$rc secs=$((end-start)) errors=$errs warnings=$warns :: ${pass:-NO_PASS_MARKER}" > result.txt
grep -hE 'HEAD_STREAM_METRIC|SCHEDULE_PROFILE operator=9|LLM_TRAFFIC operator=9|LINEAR_STREAM_(METRIC|STALLS)' run.log 2>/dev/null | sed 's/^# //' > metrics.txt
cat result.txt
