#!/bin/bash
# usage: run_app.sh <xcelium|questa>; candidate RTL + pretrained 2026-10-07 export
# + verification-only clamp census bind, outside run_application.ps1.
set -u
sim=$1
root=$HOME/npu_phase1b_20261025
d=$root/app/${sim}
rm -rf "$d"; mkdir -p "$d/tests/full_rtl"; cd "$d" || exit 1
source /etc/profile.d/modules.sh; module use /tools/modulefiles
ALTERA_MF=/tools/Intel/intelFPGA/22.1std/quartus/eda/sim_lib/altera_mf.v
ln -s "$root/cand/Verilog Source code" rtl
ln -s "$root/cand/Verilog Source code" "Verilog Source code"
cp -r "$HOME/npu_clamp_20261024/src/tests/full_rtl/build" tests/full_rtl/build
( cd tests/full_rtl/build && sha256sum -c "$root/export.sha256" ) > export_check.txt 2>&1 || { echo "export hash mismatch"; exit 1; }
{ echo rtl/npu_pkg.sv; echo rtl/llm_pkg.sv
  for f in rtl/*.sv; do b=$(basename "$f"); [ "$b" = npu_pkg.sv ] || [ "$b" = llm_pkg.sv ] || echo "$f"; done
  echo "$root/cand/tests/full_rtl/application_tb.sv"; echo "$root/cand/tests/full_rtl/clamp_monitor.sv"; } > sources.f
sha256sum $(cat sources.f) tests/full_rtl/build/*.mem tests/full_rtl/build/config.svh > source_hashes.txt
top=tb_full_rtl_application
start=$(date +%s)
if [ "$sim" = xcelium ]; then
  module load cadence/xcelium/23.03
  xrun -64bit -timescale 1ns/1ps -incdir rtl -incdir tests/full_rtl/build -f sources.f "$ALTERA_MF" -top "$top" -top llm_clamp_binder -access +rw -l run.log > console.log 2>&1
  rc=$?; errs=$(grep -cE '\*(E|F),' run.log); warns=$(grep -cE '\*W,' run.log)
else
  module load siemens/questasim/2024.1
  { vlib work && vlog -work work "$ALTERA_MF" -l comp_mf.log &&
    vlog -sv -svinputport=var -work work +incdir+rtl +incdir+tests/full_rtl/build -f sources.f -l comp.log &&
    vsim -c -onfinish exit -lib work -l run.log "$top" llm_clamp_binder -do "run -all; quit -f"; } > console.log 2>&1
  rc=$?; errs=$(cat comp.log run.log 2>/dev/null | grep -cE '^(# )?\*\* (Fatal|Error)'); warns=$(cat comp.log run.log 2>/dev/null | grep -cE '^(# )?\*\* Warning')
fi
end=$(date +%s)
pass=$(grep -hE '^(# )?[A-Z0-9_]+_PASS( |$)' run.log 2>/dev/null | tail -1)
echo "$sim $top rc=$rc secs=$((end-start)) errors=$errs warnings=$warns :: ${pass:-NO_PASS_MARKER}" > result.txt
grep -hE 'CLAMP_(SITE|PHASE|MONITOR)' run.log | sed 's/^# //' > clamp.txt
cat result.txt
