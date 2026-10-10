# postscale.sv — Change scale, add bias and saturation

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive · Legacy](../../archive/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| Read first | [Legacy architecture](../../design/legacy/architecture.md) |
| Related implementation | [scale_compose.sv](scale_compose.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Status:** In use — postscale_finish after registers in ternary_mul; postscale maintains combinational interface for checking.

**Source:** [postscale.sv](<../../../Verilog%20Source%20code/postscale.sv>).

Input ports declared clearly `wire logic` under `default_nettype none` for Xcelium
so that net type does not have to be inferred (NODNTW). Width/signedness and arithmetic remain unchanged.

## At a glance

| Item | Description |
|---|---|
| Responsibility | The file has two modules. `postscale` holds the combinational interface: accumulator S18 multiplied by U24, RNE then adds bias and saturation. `postscale_finish` only receives rounded S42 then adds bias S32/clamp. The ternary engine latches product and rounded result before calling the finish module; it does not instantiate the entire combinational chain anymore. |

## Overall architectural diagram

![postscale.sv — overview](../../diagrams/previews/51_postscale.sv_1.svg)

[Editable draw.io — postscale.sv — overview](../../diagrams/architecture.drawio) · Page `51_postscale.sv_1`.

A solid line represents data, a dashed line represents format/control. Both modules in this file are combinational; the engine's product/round registers are in [ternary_mul](ternary_mul.sv.md), not in interface `postscale`.

## Main flow

1. S18×U24 just accumulated to S42. M has a zero bit added before casting to signed so as not to change the meaning of U24.
2. `rne_shift42` keeps the floor quotient and guard/sticky/parity like RNE S64. When r≥42, all S42 values are rounded to zero; the minimum S42 at r=42 is tie −0.5 and chooses even zero.
3. Rounded S42 adds bias S32 in S43, without cutting intermediate bits. Bias is already in output units, so it is added after rounding.
4. `postscale_finish` sign-extends S43 when calling the general saturation function, while also reporting overflow according to the selected S16/S32 format.
5. The combinational interface is still used for reference regression. The engine calls `postscale_finish` after SCALE_PRODUCT → SCALE_ROUND → SCALE, adding two clocks per output row.

[12.720 postscale case](../../../tests/results.json) checks equivalence with the wide reference, including shift 0…63, accumulator/M/bias extrema, and clamp. [Timing hub](../../verification/timing/README.md) records Fmax impact and model cycles.

## Important state / datapath groups

### [Lines 1–26: Combinational postscale interface](<../../../Verilog%20Source%20code/postscale.sv#L1>)

**Purpose.** Wrapper keeps accumulator/M/r/bias ports as before. S42 product is RNE rounded with correct width; module finish performs bias addition/clamp. Wrapper has no clock or handshake.

### [Lines 27–46: Bias adder S43 and shared saturation](<../../../Verilog%20Source%20code/postscale.sv#L27>)

**Purpose.** Rounded S42 added to bias S32 in S43. The two outputs are clamped in parallel; output_s32 selects the overflow check domain. The engine is registered, and the combinational wrapper uses a single implementation finish.

#### Hardware block diagram of the group

![postscale.sv — detail 1](../../diagrams/previews/52_postscale.sv_2.svg)

[Editable draw.io — postscale.sv — detail 1](../../diagrams/architecture.drawio) · Page `52_postscale.sv_2`.
