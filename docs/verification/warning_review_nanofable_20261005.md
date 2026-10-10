# NanoFable synthesis and fitter warning review

<!-- reading-navigation:start -->
[Documentation](../README.md) → [Archive](../archive/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Historical context](../archive/README.md) |
| Continue / related lookup | [Current evidence](optimization_status.md) |
<!-- reading-navigation:end -->

> **Category: REVIEW — 2026-10-05 snapshot.** This snapshot must not determine current architecture, live status or active tasks.

Scope: the recorded `nanofable_long_20261005` synthesis log and incomplete fitter log. The user requested fixes for material RTL/ASIC problems and acceptance of warnings confined to the FPGA demonstration backend.

## Decision

No critical RTL functional defect was identified in these diagnostics. No RTL or backend configuration was changed by this review. All diagnostics remain visible; no suppression, timing exception or gate relaxation was added.

Synthesis completed with zero errors and 22 warnings. The incomplete fitter log contains two ordinary warnings and one Critical Warning. The latter concerns FPGA package pin locations, not portable compute/control logic. An incomplete fit is not a timing PASS.

| Diagnostic | Evidence and impact | Disposition |
|---|---|---|
| 10036: `chunk_q` assigned but unread | Declaration at `llm_soc.sv:282`; assignments at reset and linear/head row transitions have no consumers. Synthesis removes the unused state. No handshake, address or numeric output depends on it. | Accept harmless redundant state; no cleanup required for this task. |
| 10027: prompt-array index | `prompt_memory[0:127]` at line 276; line 726 concatenates a three-bit constant generated bank (0..7) and four address bits (0..15). Each generated read covers its 16-entry bank, and the eight banks collectively cover 0..127. No address truncation or out-of-bounds value is indicated by this expression. | Reviewed and accepted. |
| 10027: head-cache index | `input_cache_q[0:11]` at line 291; line 767 uses `{2'b0, head_input_chunk}`. The head engine exports a two-bit chunk and only captures four responses, so this consumer intentionally selects entries 0..3. Other linear operations use the larger cache extent. | Reviewed and accepted; widening the numeric range would change the intended selection. |
| 287013: unused `data_b` / `rden_a` | Six messages refer to Quartus-generated `altsyncram_*.tdf` memory implementations. These are technology-leaf/backend diagnostics. | Accept for this FPGA backend. Do not edit generated vendor files. |
| 276020: RAM pass-through logic | Quartus adds logic to preserve RTL read-during-write behavior for `output_memory` and attention `score_memory`. Host output reads are accepted only while the graph is idle (`llm_soc.sv:457..458`); token writes occur in `G_ADVANCE` (line 674). Attention score writes and the combinational score read are explicit in `llm_attention_engine.sv:33,65`. | Retain RTL semantics and implementation diagnostics. A future ASIC SRAM binding must preserve the required read behavior/latency or provide equivalent forwarding. This is not an observed functional failure. |
| 13024 / 13410: constant debug outputs | Ten child messages plus the summary. `pc_debug` explicitly zero-extends the seven-bit position; `instr_debug` zero-extends graph/debug state. `ENABLE_DEBUG_INDEX=0` ties the seven operation-index bits to zero (`llm_soc.sv:354..368,617`). | Intentional constants; accept. |
| 292013: LogicLock subscription | Quartus edition/license capability warning. No portable datapath change is requested by it. | Accept FPGA tool/backend warning. |
| 15714: incomplete I/O assignments | FPGA electrical/placement configuration. | Accept for the EDA demonstration; physical pin assignment belongs to a future concrete board backend. |
| **169085: Critical Warning, 125 unassigned package pin locations** | No board is being targeted. The FPGA fitter may assign demonstration pins automatically. ASIC pad planning uses a separate technology/physical flow. | **Accept as backend-only despite the tool severity label. Do not invent a board pinout or modify portable RTL.** |

## Existing verification applicability

A read-only SHA-256 comparison during this review confirms that all 41 current RTL/LUT assets match:

- `tests/full_rtl/unit_results.json`: all seven synthetic groups PASS, including operator, protocol, selection and autonomous graph checks.
- `docs/verification/portable_elaboration_opt_final4/results.json`: vendor-free elaboration evidence.
- `docs/verification/timing/nanofable_long_20261005/sources_before.json`: the source snapshot for the reviewed synthesis.

No new simulation or synthesis was run by this review. Existing numeric expectations and test coverage were unchanged. These checks are supporting evidence, not a proof of every possible input or ASIC signoff.

The fitter/application interruption remains unresolved and is separate from the warning classification. The reviewed logs contain no diagnostic establishing its cause. Pretrained execution still requires exact-current full-top all-corner timing of at least 100 MHz, nonnegative setup/hold/recovery/removal/pulse slack, zero TNS, no unconstrained paths and the current all-seven-unit PASS. FPGA-only warning acceptance does not waive any of those gates.

If subsequent stages produce new latch, functional, memory-contract, illegal-resource or timing-failure diagnostics, review them separately; this decision applies only to the diagnostics listed above.
