# Verification of llm_soc on the server

<!-- reading-navigation:start -->
[Documentation](../README.md) → [04 · Verification](../04-verification/README.md) → This page

| Reading guide | Document |
|---|---|
| Continue / related lookup | [Current evidence](optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE.**

[Flow server and configuration](../../tools/server/README.md) is the current running guide
on branch `remote`. Run Xcelium/Genus in Slurm allocation; the entry points
for local ModelSim/Questa/Verilator/Quartus have stopped working.

| Verification level | Entry point from repo root on compute node | Scope |
|---|---|---|
| Full regression | `python3 tools/server/run_flow.py --stage test --tag TAG` | 7 graph groups + linear stream + host cancel |
| Debug group | `--stage test --only tb_llm_ram --tag TAG` | Selected groups, not full PASS |
| Synthesis | `--stage syn --lib /approved/cells.lib --tag TAG` | Genus mapped netlist, design/area/timing reports |
| Test + synthesis | `--stage all --lib /approved/cells.lib --tag TAG` | Two claims recorded separately |
| Application | `--stage application --fixture PATH --tag TAG` | Functional checkpoint token matching |
| Legacy shared RTL | `--stage legacy --tag TAG` | 9 legacy tops using Xcelium |

According to [server instructions](../../tools/server/README.md) before connecting; do not
commit/upload credential or VPN config. Transfer and allocation require appropriate authorization.
Transfer has been confirmed by the user; X11 and the Xcelium/Genus modules have
been checked on `black`. Use the launcher `slurm_x11.sh` from SSH or RDP and keep
`--x11`; Liberty still needs confirmation before synthesis.
`--check-inputs` check file/config/manifest, not simulator or synthesis PASS.

Reports are located at `reports/TAG`, database at `build/TAG`. New tags are mandatory; runner
stores node/job/commands/hashes/markers and rejects input switched between runs. Long jobs
only check initially once then hand over according to server instructions, no poll/relaunch.

Default portable RAM; do not compile vendor RAM leaf. Keep numeric and
protocol assertions. Backend/tool switch requires full regression; FPGA timing,
Unit PASS history and application PASS are separate claims, they do not automatically transfer to
new source. Genus completion does not confirm timing closure or ASIC signoff.

[Status/evidence before migration](optimization_status.md) remains unchanged.
Old local commands and progress can be seen in [history](../history/full_rtl_verification_development.md)
and Git history. Do not run runner snapshot to replace the current source.
