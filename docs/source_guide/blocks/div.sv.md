# div.sv — Unsigned sequential divider

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [02 · Architecture](../../02-architecture/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Read first | [Full RTL graph](../full_graph.md) |
| Related implementation | [llm_attention_normalize.sv](llm_attention_normalize.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Status:** In use — internal scalar.

**Source:** [div.sv](<../../../Verilog%20Source%20code/div.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | This is an unsigned restoring divider, not a vector DIV instruction. Each step shifts one bit of the numerator to the remainder, tries to subtract the denominator, and generates one bit of the quotient. Current `llm_soc` and attention-normalization instances use NUM_W=64/DEN_W=32. Legacy NORM uses 55/32; scale_compose uses 48/25. The default parameter 64/32 is kept for generic helper and verification. |

## Overall architecture diagram

![div.sv — overview](../../diagrams/previews/18_div.sv_1.svg)

[Editable draw.io — div.sv — overview](../../diagrams/architecture.drawio) · Page `18_div.sv_1`.

## Main flow

Start when free to latch numerator/denominator. Each busy cycle advances one bit; after NUM_W steps, returns quotient/remainder and done. Divide by 0 returns a quotient of all 1s, remainder gets numerator cast to DEN_W bits, div_zero=1; the caller must handle the error flag and not use it as a valid mathematical result.

1. Divider is unsigned; signed operations must handle sign/magnitude in the caller. Start is only accepted when not busy.
2. `q_work` initially contains numerator. Each cycle, one bit is shifted into `rem_shift`.
3. If remainder is large enough, hardware subtracts the denominator and sets the new quotient bit to 1; otherwise, the new bit is 0.
4. After NUM_W steps, the final quotient and remainder are latched along with the done pulse.
5. Division by zero ends immediately with `div_zero=1`; the quotient being all 1s is just a hardware convention, not a valid quotient.

**RTL convention.** Counter initialized with `CW'(NUM_W)` to specify the width to hold the step count; loop works with NUM_W bit numerator. Remainder of division by zero uses `DEN_W'(numerator)`, avoiding part-select exceeding range when denominator is wider than numerator. Divider still returns quotient/remainder using sequential algorithm; divide-by-zero and start/busy/done interface remain unchanged.

## Important state / datapath groups

### [Lines 1–25: Interface and width](<../../../Verilog%20Source%20code/div.sv#L1>)

**Purpose.** Intermediate remainder is DEN_W+1 wide to preserve carry when shifting.

**How this part of the code works.** This group defines interfaces, widths, types, or intermediate signals. It creates a structure for subsequent processing groups to use, not yet representing a separate runtime step.

**Main signals and data.** `start`: request to start a transaction; `numerator`: numerator of the division; `denominator`: denominator of the division; `busy`: block being processed; `done`: completion pulse; `div_zero`: divider signals zero denominator; and 8 other auxiliary signals in the code segment.

### [Lines 26–37: A division step](<../../../Verilog%20Source%20code/div.sv#L26>)

**Purpose.** Translate the remainder and quotient; if large enough, subtract the denominator and set the new quotient bit to 1.

**How the code section works.** There is combinational logic: output/intermediate is calculated from the current input; default values at the beginning of the block help avoid deducing latches.

**Main signals and data.** `rem_shift`: remainder after shift/subtract in the current step; `rem_work`: remainder being accumulated; `q_work`: numerator/quotient register in the division loop; `q_next`: quotient after one divider step; `den_reg`: locked denominator.

**Points to read carefully.** This is a step of restoring division. `q_work` both holds the unprocessed numerator bits and gradually becomes the quotient as each new bit is shifted in from the lower side.

#### Hardware block diagram of the group

![div.sv — detail 1](../../diagrams/previews/19_div.sv_2.svg)

[Editable draw.io — div.sv — detail 1](../../diagrams/architecture.drawio) · Page `19_div.sv_2`.

### [Lines 38–58: Reset/start](<../../../Verilog%20Source%20code/div.sv#L38>)

**Purpose.** Catch the case denominator=0 before the loop; if valid, keep the denominator and the counter.

**How the code works.** There is sequential logic: register/FSM only updates on the clock edge; nonblocking assignment reads the old value on the right-hand side and then latches simultaneously.

**Key signals and data.** `busy`: current processing block; `done`: completion pulse; `div_zero`: divider signals zero sample; `quotient`: quotient; `remainder`: remainder; `q_work`: numerator/quotient register in the division loop; and 6 other auxiliary signals in the code segment.

### [Lines 59–72: Loop](<../../../Verilog%20Source%20code/div.sv#L59>)

**Purpose.** Latch q_next/rem_shift, decrease count. When the old count=1, output the result of the final step.

**How the code works.** The statements belong to the same processing branch/phase and must be read consecutively; separating each line will lose the conditional and data relationships.

**Key signals and data.** `busy`: block being processed; `q_work`: numerator/quotient register in the division loop; `q_next`: quotient after one divider step; `rem_work`: accumulating remainder; `rem_shift`: remainder after shift/subtract in the current step; `count`: iteration step counter; and 3 other auxiliary signals in the code segment.
