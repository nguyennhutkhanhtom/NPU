# Full RTL language inference

[Design and implementation status](../../docs/design/full_rtl_language.md) · [Language demo hub](../../docs/demos/language.md)

`run_units.ps1` checks arithmetic, operators and the autonomous graph with synthetic fixtures. It does
not load a trained application checkpoint. `run_application.ps1` first checks
the exact full-graph synthesis/timing evidence, source/config hashes and unit
results. It refuses to run the application below 100 MHz or after source edits.

The six groups are SIMD/LUT arithmetic, graph operators, host protocol, SRAM
contracts, selection edge cases and a host-loaded synthetic graph. Selection
checks masked IDs and stable ties at S32_MIN. SRAM checks two-edge adapter
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

```powershell
./tests/full_rtl/run_units.ps1
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag fullrtl100_final -QuartusBin C:/intelFPGA_lite/18.1/quartus/bin64
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/fullrtl100_final/manifest.json
```

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
adapter carries a register-merging attribute; compute RTL uses no vendor macros.
