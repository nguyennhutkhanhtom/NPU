# RTL Policy Overview

<!-- reading-navigation:start -->
[Documentation](../README.md) → [Decisions](../decisions/README.md) → This page

| Reading guide | Document |
|---|---|
| Read first | [Architecture map](../02-architecture/README.md) |
| Continue / related lookup | [Coding readiness review](../reviews/rtl_lowrisc_readiness_20261010.md) |
<!-- reading-navigation:end -->

> **Category: POLICY.** Maintain clear hardware structure, timing boundary, and register ownership.

## Overview

| Scope | Rule |
|---|---|
| Sequential logic | One clear owner per register/array element; no multiple drivers or unintended latches |
| FSMs | Explicit state transitions, clock enables, pipeline registers, and handshakes |
| Replication | `generate` for module/interface replication and independently owned lane registers |
| Procedural loops | Statically determinable bounds; review the resulting combinational depth and replicated hardware |
| Helpers | Small pure combinational or elaboration functions only |
| Memory | Technology macros confined to leaves behind explicit portable contracts |

## State and control

- Keep FSM transition, register update, memory request, and response capture clearly visible in RTL.
- Do not use synthesizable tasks or helper abstractions that obscure datapath, state, timing, or important transactions.
- Prioritize clear register/lane ownership. Procedural loops with limits can be used when the resulting hardware structure remains clear.
- Use clock enable. Do not use combinational logic to gate the clock; technology clock gating belongs to the integration boundary.
- Do not use simulation delay, force/release, file I/O, or system-task behavior in RTL compute/control.

## Arithmetic

Explicitly show width, signedness, fixed-point scale, extension, truncation,
rounding, and saturation. Use normally synthesizable operators when they clearly describe
the desired hardware structure.

Keep the intention of avoiding multiplier/divider: do not change the NPU structural datapath
by `*`, `/` at runtime or vendor arithmetic IP if no architectural
change has been clearly approved along with verification for arithmetic/PPA. Allow geometric/index
constant operations at elaboration.

Keep the helpers purely about saturation, rounding, extension, and constant geometry
on a small scale. The arithmetic pipeline must be located in an explicit module.

## Memory and reset

- Determine read latency, write commitment, collision behavior, reset cancellation, and response validity at each adapter boundary.
- Reset control/validity as required; do not use a non-reset payload if there is no valid transaction yet.
- Preserve committed SRAM contents when the reset contract requires data retention.
- Do not infer that resetting a request will cancel a committed write.
- Quartus memory primitive can only be in `quartus_word_ram`; assignments regarding placement/routing/pin/physical belong to the backend.
- SRAM ASIC, clock-gating cell and other technology cells require a separate wrapper or integration layer with an explicit portable contract.

## Should Use / Avoid Using

| Should Use | Avoid Using |
|---|---|
| Named pipeline valid and operand registers | A helper that implicitly advances transactions |
| Explicit extension before addition and a named rounding step | Unsized arithmetic with accidental truncation |
| Static lane replication with clear owners | Runtime-bounded hardware loops |
| Adapter response-valid and commit/busy signals | Assuming that request acceptance means completion |

## Related Documents

[Current numeric contracts](full_rtl_language.md#arithmetic-contracts) · [Memory binding](asic_memory_binding.md) · [Verification](../verification/README.md) · [Repository working policy](../../AGENTS.md)
