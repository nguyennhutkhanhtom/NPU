# Full RTL language inference

[Design and implementation status](../../docs/design/full_rtl_language.md) · [Language demo hub](../../docs/demos/language.md)

`run_units.ps1` checks arithmetic, operators and the autonomous graph with synthetic fixtures. It does
not load a trained application checkpoint. `run_application.ps1` first checks
the exact full-graph synthesis/timing evidence, source/config hashes and unit
results. It refuses to run the application below 100 MHz or after source edits.

The seven groups are actual Intel RAM-IP/model contract comparison, SIMD/LUT
arithmetic, graph operators, host protocol, SRAM contracts, selection edge cases
and a host-loaded synthetic graph. FPGA protocol/selection/graph/application
use the default USE_QUARTUS_MEMORY=1 and ModelSim `-L altera_mf_ver`. Operator
fixtures explicitly use the portable model backend to initialize numeric cases;
RAM-IP comparison verifies identical behavior without internal memory seeding. Selection
checks masked IDs and stable ties at S32_MIN. SRAM checks five-edge adapter
reads, queued writes, collisions, consecutive requests and reset cancellation.
Operator coverage includes reserved-code rejection, signed
nonuniform RMSNorm and 128-position attention on the final KV tile. The graph
test checks four layers, two-token prefill, three RTL-selected tokens and causal
cache reads; its deterministic fixture is verification, not model quality.
The runner records FAIL on errors and checks source/test hashes before PASS.

`llm_soc` uses `reset_release`: asynchronous assertion, two rising edges before
internal reset releases. Keep host requests asserted until ready; SRAM storage
survives reset while queued operations/validity are canceled. Protocol tests
check both release edges and immediate cancellation. Operator fixtures complete
reset release before setting numeric inputs or internal operation state. Expected
values and operation latency checks remain unchanged.

The installed Questa Starter nodelocked license permits one running simulation
session. Finish the active regression before starting another simulation or an
optimizer profile. Quartus fitting can run independently. The first isolated
`-O5` profile was [refused before design loading](evidence/opt5_profile_license_denied/results.json);
no optimizer speed or numeric result is claimed from that attempt.
`-RtlDir` permits isolated candidates; candidate hashes cannot pass the trained
application gate unless they match the current main RTL and timing evidence.

The application host supplies checkpoint words, prompt token IDs and generation
configuration. RTL owns attention, KV cache, head and autoregressive selection.
The independent CPU integer model supplies expected values solely for verification.
The application testbench observes each completed RTL token through a read-only
monitor and stops immediately on an unexpected count or token mismatch. Final
host reads still check every returned token and write `rtl_tokens.txt`. Expected
IDs never drive a DUT port or internal state. The monitor has a
[compile-only check](evidence/application_monitor_compile/results.json); its
trained application run remains blocked until the full hardware/unit gate passes.
Application preparation records source/runner hashes and all four generated
input files. Finalization rejects stale compile/runtime logs, changed inputs,
unreviewed warnings and missing actual Intel RAM-model loading. PASS means
RTL/reference continuation IDs match; text quality is explicitly NOT_ASSESSED
until the actual RTL-decoded paragraph is reviewed. No application or checkpoint
reference inference is run before the hardware/unit gate.

The installed hardware tools are Quartus Lite25.1std and official Questa
Altera Starter2025.2; ModelSim Intel Starter20.1 remains available. The archived
[logic6q5 seven groups](evidence/logic6q5_all_units/results.json) PASS with the
official25.1 RAM model and zero compile/runtime warnings. Graph:196619host
commands, two-token prefill, three RTL-selected tokens,16layer executions and
4229462compute clocks. This is synthetic verification, not pretrained text.
Current33-source explicit-RTL refactor requires a fresh regression.

`memory_model.py` compiles the official `altera_mf.v` from the Quartus installation
recorded by timing commands. It verifies source/compiler/library-object/compile-log
hashes. Questa uses optimizer design-unit reports to prove the actual selected
RAM source/library; ModelSim uses its explicit library loading log. Vendor source
and compiled libraries stay in ignored caches. A changed compiler/model requires
a fresh cache. The older [ram25 archive](../../docs/verification/memory_ip/ram25/results.json)
contains its original helper version, preserving historical helper hashes.

Questa fixtures retain all numeric expected values. Portable RAM is seeded through
its leaf write ports; one-time scalar/control initialization uses deposit or
force/release so the RTL `always_ff` remains the sole register writer. Signed
minimum bit patterns are explicit. No simulator diagnostic is suppressed.

```powershell
python tests/full_rtl/memory_model.py --timing docs/verification/timing/fullrtl100_logic5/manifest.json --sim-bin C:/altera_lite/25.1std/questa_fse/win64 --output tests/full_rtl/build/questa25_model
./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_logic5/manifest.json -WorkLibraryName NEW_WORK -EvidenceTag NEW_UNUSED_TAG
```

Do not recompile/overwrite an active work library or evidence tag. Current jobs
and reproduction commands are in [TASK_STATE](../../TASK_STATE.md). Application
preparation/reference execution remain blocked until exact-current hardware
AND all-seven-unit gates pass.

```powershell
./tests/full_rtl/run_units.ps1
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag fullrtl100_final -QuartusBin C:/altera_lite/25.1std/quartus/bin64
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/fullrtl100_final/manifest.json
```

Parameter read now takes five internal edges plus host lane selection and
frontend response. Parameter write ACK waits for leaf commit. Tests permit
16 host edges and reject stale responses across ten cancellation phases;
the expected data and tokens are unchanged. `O_FINISH` waits for queued
vector/cache writes before reporting completion.

The current Questa runner archives all seven groups and actual Intel RAM-IP
elaboration bindings directly. Retired native/merge helpers are preserved in
[cleanup history](../../docs/history/helper_cleanup1/manifest.json); they have
no current runner callers. Older [select3 units](evidence/select3_units/unit_results.json)
verify their archived pre-IP source and cannot gate this revision. Windows
Application Control blocks some native executables; no policy bypass is used.

The new host uses registered transactions: hold `host_en`, address, write flag
and data until `host_ready`; then deassert enable for at least one clock. All
addresses are byte addresses aligned to four bytes. Writes while running have
no effect. Read status to determine completion before reading output IDs.

Dropping `host_en` before the execution edge cancels the write. After execution
accepts it, dropping enable cancels its response but the accepted SRAM write
may still commit; the host must not assume rollback. Reset cancels uncommitted
queue entries and retains committed storage. An additional [host-only probe](host_cancel_contract.sv)
checks all seven cancellation phases, the next request after one idle edge,
and each new write's own leaf commit before ACK: [14checks PASS](evidence/host_cancel_gap1/results.json),
Questa2025.2/actual Quartus25.1 RAM,0compile/runtimewarnings. The preceding
[two-idle-edge probe](evidence/host_cancel_gap2/results.json) is retained separately.
This does not execute the graph or checkpoint and does not alter the eight
inputs of the current seven-group regression.

After `run_units.ps1` creates `build/sources.f`, reproduce this optional probe
from the repository root with a fresh library and binding report:

```powershell
$simBin = 'C:/altera_lite/25.1std/questa_fse/win64'
& "$simBin/vlib.exe" tests/full_rtl/build/NEW_PROBE_WORK
& "$simBin/vlog.exe" -sv -svinputport=var -work tests/full_rtl/build/NEW_PROBE_WORK '+incdir+Verilog Source code' -f tests/full_rtl/build/sources.f tests/full_rtl/host_cancel_contract.sv
& "$simBin/vsim.exe" -c -onfinish exit '-voptargs=-duselectreport=tests/full_rtl/build/NEW_PROBE_BINDING.json' -L tests/full_rtl/build/questa25_model/altera_mf_ver -L tests/full_rtl/build/NEW_PROBE_WORK -lib tests/full_rtl/build/NEW_PROBE_WORK tb_host_cancel_contract -do 'run -all; quit -f'
```

| Window/register | Address | Meaning |
|---|---:|---|
| Parameters | `0x00000000..0x000bfffc` | 768 KiB SRAM, 32-bit host lanes |
| Prompt IDs | `0x00100000..0x001001fc` | 128 × token IDs |
| Output IDs | `0x00200000..0x002001fc` | RTL continuation IDs, readable when idle |
| Status | `0x00400000` | bits 0 running, 1 ready, 2 error, 3 overflow; bits 11:4 output count |
| Prompt count | `0x00400004` | 1..127; prompt+maximum continuation ≤128 |
| Maximum new tokens | `0x00400008` | Default 96 |
| Start | `0x0040000c` | Write bit 0=1 |
| Temperature | `0x00400010` | U8/F8; default 166; zero selects greedily |
| Random seed | `0x00400014` | Xorshift32; zero is replaced by one |
| Minimum new tokens | `0x00400018` | EOS masked until this many IDs; default 64 |

SRAM payload is 768 KiB parameters, 384 KiB KV cache and 9 KiB vector workspace.
Quartus uses a C9 device to verify packing and timing. The replaceable memory
adapter isolates altsyncram M10K from compute RTL. AUTO_DSP_RECOGNITION OFF
and DSP_BLOCK_BALANCING LOGIC ELEMENTS prohibit DSP inference; the application
gate also requires actual fit summary DSP=0 and PLL=0.


Current arithmetic timing revision pipelines SIMD byte products and pair sums:
exact done latency9 clocks, reset coverage9 phases,503transactions and unchanged
S128 expected products/sums. Scalar S39×S25 product has3 arithmetic stages;
128extra independent signed-extreme/random checks supplement all17operators.
The graph retains every numeric/token/causal/visit check and196619host commands;
only the stage-count watchdog changes4M→5M compute clocks and100ms total.
Bytes1 hardware completed0DSP/0PLL but FAIL89.60MHz/setup+hold; its six groups
PASS, graph cancelled for measured control/locality fixes. Current tag
fullrtl100_control1 adds ternary-code capture, exp-delta and scalar-clamp pipeline
states (102onehotstates), memory-local enables and direct LVDS input clock buffer.
Operators also add128clamp cases: all eight groups, linear/attention, S64 extremes,
S24 endpoints and adjacent values, alternating overflow/plain values to detect
stale private flags. All existing numerical expectations remain unchanged.
Control1 sixgroupsPASS:17operators/3460checks/scalar128/clamp128,0runtimewarnings.
Fit0DSP/PLL/DLL/HSSI but timingFAIL92.75MHz/setup-hold-recovery. Graph cancelled
for the next measured host mux fix; sixgroups/logs archived separately. Fresh
unit/fullgraph and all-corner timing proof are required; application remains gated.
# Test scheduling for portable logic multiplication

`./tests/full_rtl/run_units.ps1 -UnitsOnly -EvidenceTag NEW_UNUSED_TAG` runs the
six arithmetic/memory/protocol/operator groups while fitting is in progress.
Its success status is `SIX_GROUPS_PASS_GRAPH_PENDING`, never aggregate `PASS`.
Default execution still runs all seven groups, including the autonomous graph;
`check_gate.py` still requires all seven PASS for the exact current source.
The runner saves an immutable initial hash snapshot before compilation under
`build/TAG_modelsim_start.json`. Tags cannot overwrite an existing snapshot.
No expected values or testcases are relaxed by changing execution order.

The math group exhausts 1536 small-width signedness/truncation/one-bit products
against independent testbench arithmetic, then retains the existing 503 SIMD
transactions, reset cancellation and LUT checks. Arithmetic operators are
permitted in independent testbench/reference code only, not hardware datapaths.

Preceding attention1 [seven-group archive](evidence/attention1_all_units/results.json) PASS0compile/runtimewarnings after moving accumulator clear to head entry; full graph4229462compute clocks, three RTL-selected tokens,16layer executions and causal checks. [Vendor-free full-top elaboration](../../docs/verification/portable_elaboration_attention1/results.json) also PASS, run0/no weights/inference. Full-top attention1 timing FAIL92.19MHz/setup+recovery; application gate is closed.

Current cache1 separates generated continuous KV payload FFs from the held binary operand. Consumers still follow cache valid; no FSM state/clock/latency/expected-value change. [Seven groups](evidence/cache1_all_units/results.json) PASS0compile/runtimewarnings, graph4229462compute clocks/three RTL-selected tokens/16layer executions/causal checked; full timing FAIL73.97MHz/setup+recovery; hold/removal/pulse PASS every corner/UCP0. Host reset still clears response immediately; QSF global-routing request is backend-only, not compute/control IP or ASIC signoff. [Current vendor-free elaboration](../../docs/verification/portable_elaboration_cache1/results.json) PASS24module units/14names/0errors0warnings, run0/no weights/inference. Preceding timing evidence applies to its archived attention1 source; no current100MHz or trained application PASS.

Backend cache2 removes the forced-global QSF routing request after cache1 recommendations identified its failing path. No RTL, test input, SRAM contract or SDC change; exact cache1 seven-group/vendor-free PASS remains applicable to the same source. Fresh full synthesis/fit/all-corner timing is running; no application gate is open.
