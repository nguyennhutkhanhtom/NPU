#!/bin/bash
# usage: lint_one.sh <base|cand> ; SpyGlass lint/lint_rtl on portable llm_soc
set -u
ver=$1
root=$HOME/npu_phase1b_20261025
d=$root/lint/$ver
rm -rf "$d"; mkdir -p "$d"; cd "$d" || exit 1
source /etc/profile.d/modules.sh; module use /tools/modulefiles; module load synopsys/spyglass/T-2022.06
ln -s "$root/$ver/Verilog Source code" rtl
files="rtl/npu_pkg.sv rtl/llm_pkg.sv"
for f in rtl/*.sv; do b=$(basename "$f"); [ "$b" = npu_pkg.sv ] || [ "$b" = llm_pkg.sv ] || files="$files $f"; done
sha256sum $files > source_hashes.txt
cat > run.tcl <<EOF
new_project lint_$ver -force
read_file -type verilog {$files}
set_option enableSV12 yes
set_option incdir {rtl}
set_option top llm_soc
set_option mthresh 65536
set_option param {llm_soc.USE_QUARTUS_MEMORY=0}
current_methodology \$env(SPYGLASS_HOME)/GuideWare/latest/block/rtl_handoff
current_goal lint/lint_rtl -top llm_soc
run_goal
write_report moresimple > moresimple.rpt
write_report summary > summary.rpt
save_project
exit -force
EOF
sg_shell -tcl run.tcl > sg.log 2>&1
echo "lint $ver rc=$? $(grep -cE '^\[' moresimple.rpt 2>/dev/null) lines"
