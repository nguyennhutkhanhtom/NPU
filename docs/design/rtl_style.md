# Synthesizable RTL policy

> **Category: POLICY.** Keep hardware structure, timing boundaries and register ownership explicit.

## At a glance

| Area | Rule |
|---|---|
| Sequential logic | One clear owner per register/array element; no multiple drivers or unintended latches |
| FSMs | Explicit state transitions, clock enables, pipeline registers and handshakes |
| Replication | `generate` for module/interface replication and independently owned lane registers |
| Procedural loops | Statically determinable bounds; review the resulting combinational depth and replicated hardware |
| Helpers | Small pure combinational or elaboration functions only |
| Memory | Technology macros confined to leaves behind explicit portable contracts |

## State and control

- Keep FSM transitions, register updates, memory requests and response capture in visible RTL.
- Do not use synthesizable tasks or helper abstractions that hide significant datapaths, state, timing or transactions.
- Prefer explicit register/lane ownership. A bounded procedural loop is acceptable when its hardware remains clear.
- Use clock enables. Ordinary combinational clock gating is prohibited; technology clock gating belongs at the integration boundary.
- Do not use simulation delays, force/release, file I/O or system-task behavior in compute/control RTL.

## Arithmetic

Make width, signedness, fixed-point scale, extension, truncation, rounding and saturation explicit. Use ordinary synthesizable operators where they express the intended hardware clearly.

Preserve intentional multiplier/divider avoidance: do not replace the structural NPU datapaths with runtime `*`, `/` or vendor arithmetic IP without an explicitly authorized architecture change and numerical/PPA verification. Constant geometry/index arithmetic at elaboration is permitted.

Keep pure saturation, rounding, extension and constant-geometry helpers small. Significant arithmetic pipelines belong in explicit modules.

## Memory and reset

- Define read latency, write commitment, collision behavior, reset cancellation and response validity at each adapter boundary.
- Reset control/validity as required; unreset payload must never be consumed without a valid transaction.
- Preserve committed SRAM contents when the specified reset contract requires retention.
- Do not infer that resetting a request cancels an already committed write.
- Quartus memory primitives belong only in `quartus_word_ram`; placement/routing/pin/physical assignments belong in the backend.
- ASIC SRAM, clock-gating and other technology cells require dedicated wrappers or integration layers with explicit portable contracts.

## Good / avoid

| Good | Avoid |
|---|---|
| Named pipeline valid and operand registers | A helper that implicitly advances transactions |
| Explicit extension before addition and a named rounding step | Unsized arithmetic with accidental truncation |
| Static lane replication with clear owners | Runtime-bounded hardware loops |
| Adapter response-valid and commit/busy signals | Assuming that request acceptance means completion |

## Related docs

[Current numeric contracts](full_rtl_language.md#hợp-đồng-số-học) · [Memory binding](asic_memory_binding.md) · [Verification](../verification/README.md) · [Repository working policy](../../AGENTS.md)
