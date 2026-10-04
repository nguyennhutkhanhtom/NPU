# Synthesizable RTL rules

Avoid software-like abstraction in synthesizable RTL.

- Prefer explicit RTL over procedural loops.
- Use `generate for` for structural hardware replication.
- Allow procedural `for` only for small, statically bounded hardware where explicit unrolling harms readability.
- Never use variable or unbounded loops.
- Do not use synthesizable `task`.
- Use `function` only for small, pure combinational helpers.
- Do not hide FSMs, handshakes, register updates, memory accesses, pipeline stages, or significant datapaths inside functions/tasks.
- Hardware structure and register ownership must be obvious from the RTL source.

Only the SRAM technology leaf may instantiate Quartus/Altera memory IP. Datapath and control logic must remain portable SystemVerilog made from registers, muxes, comparisons, bitwise logic, addition/subtraction and shifts. Runtime multiplication/division operators and vendor arithmetic/control IP are prohibited; implement multiplication/division structurally with these permitted operations. Constant elaboration geometry is permitted.

Preserve correct changes and immutable evidence. Do not reset/revert the workspace. Before pretrained application execution, require exact-current unit/graph PASS and full-top post-fit timing >=100 MHz at every corner, with nonnegative setup/hold/recovery/removal/pulse slack, TNS=0 and no unconstrained paths. Never mask failures with timing exceptions or relaxed tests.
