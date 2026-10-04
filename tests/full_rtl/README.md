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
`-RtlDir` permits isolated candidates; candidate hashes cannot pass the trained
application gate unless they match the current main RTL and timing evidence.

The application host supplies checkpoint words, prompt token IDs and generation
configuration. RTL owns attention, KV cache, head and autoregressive selection.
The independent CPU integer model supplies expected values solely for verification.
Application preparation records source/runner hashes and all four generated
input files. Finalization rejects stale compile/runtime logs, changed inputs,
unreviewed warnings and missing actual Intel RAM-model loading. PASS means
RTL/reference continuation IDs match; text quality is explicitly NOT_ASSESSED
until the actual RTL-decoded paragraph is reviewed. No application or checkpoint
reference inference is run before the hardware/unit gate.

```powershell
./tests/full_rtl/run_units.ps1
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag fullrtl100_final -QuartusBin C:/intelFPGA_lite/18.1/quartus/bin64
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/fullrtl100_final/manifest.json
```

Parameter read now takes five internal edges plus host lane selection and
frontend response. Parameter write ACK waits for leaf commit. Tests permit
16 host edges and reject stale responses across ten cancellation phases;
the expected data and tokens are unchanged. `O_FINISH` waits for queued
vector/cache writes before reporting completion.

The native helper now rejects protocol/selection/graph/application/all because
it does not supply the actual Intel RAM-IP simulation model. It never silently
changes USE_QUARTUS_MEMORY. Use ModelSim for the FPGA configuration.
`merge_unit_evidence.py` can combine six exact-source ModelSim units and an
independent ModelSim graph only after source/test/log hashes and actual Intel
RAM model loading agree. Older [select3 units](evidence/select3_units/unit_results.json)
verify their archived pre-IP source and cannot gate this revision. Windows
Application Control blocks some native executables; no policy bypass is used.

The new host uses registered transactions: hold `host_en`, address, write flag
and data until `host_ready`; then deassert enable for at least one clock. All
addresses are byte addresses aligned to four bytes. Writes while running have
no effect. Read status to determine completion before reading output IDs.

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
