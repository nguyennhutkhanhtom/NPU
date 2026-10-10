# norm.sv

<!-- reading-navigation:start -->
[Documentation](../../README.md) → [Archive · Legacy](../../archive/README.md) → [Module catalog](README.md)

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../../00-start-here/fundamentals.md) · [Glossary](../../00-start-here/glossary.md) |
| Learn the RTL syntax | [How to read the SystemVerilog](../../00-start-here/reading-systemverilog.md) |
| Read first | [Legacy architecture](../../design/legacy/architecture.md) |
| Related implementation | [isqrt_u64.sv](isqrt_u64.sv.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).

**Source:** [norm.sv](<../../../Verilog%20Source%20code/norm.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Legacy three-pass RMS normalization and quantization. Two shared structural multipliers, one divider and the separately defined isqrt_u64 serve the explicit pass controller. Workspace scratch and final quantized values are packed in 256-bit words. |

## Architecture diagram

![norm.sv — overview](../../diagrams/previews/41_norm.sv_1.svg)

[Editable draw.io — norm.sv — overview](../../diagrams/architecture.drawio) · Page `41_norm.sv_1`.

## Main flow

NORM makes three passes over a vector stored in the 8 KiB legacy workspace:

1. Read S16 input elements, square them in pairs, and accumulate `sum_sq`.
2. Divide by vector length, add epsilon, take integer square root, and derive a
   normalization coefficient. Read the input again, calculate normalized S24/F16
   scratch values `z`, store them in S32 cells, and track maximum absolute value.
3. Use `D=max(absmax, delta)` to derive the quantization coefficient. Read scratch
   `z`, calculate/clamp S8 `q`, and pack it into the output region.

The five `always_comb` blocks do different jobs. None stores state by itself;
the FSM and neighboring `always_ff` blocks decide when results are captured.

### `always_comb` at lines 116–169: shared arithmetic input mux

The block extracts two lanes from `read_buf`, clears both multiplier inputs and
the rounding shift, then overrides them according to the current pass:

| State | Multiplier operation | Why |
|---|---|---|
| `P1_CAPTURE` | `x0*x0` and `x1*x1` | Build two squares for `sum_sq` |
| `P2_CAPTURE` | `x0*norm_m` and `x1*norm_m` | Normalize input into scratch `z` |
| `P3_CAPTURE` | `zr0*quant_m` and `zr1*quant_m` | Quantize scratch into S8 `q` |

Static loop bound two creates two parallel operand muxes. It is not a two-cycle
loop. The state is effectively the enable selecting which arithmetic meaning is
active. Defaults of zero reduce unintended switching and cover states that do
not use the multipliers.

### `always_comb` at lines 213–219: scalar operands

`mean_with_epsilon` combines the integer quotient, the fractional quotient, and
`epsilon_q` in the common raw-square/F32 domain. `norm_num` and `quant_num`
construct powers-of-two numerators used by later divider states. This is wiring
and shifting; actual multi-cycle division begins only when `div_start` is raised
by the command mux.

### `always_comb` at lines 224–248: clamp and absolute value

The first block clamps two rounded normalized results to signed 24-bit values and
computes their unsigned magnitudes for `absmax`. The second clamps two rounded
quantized results to signed 8-bit values. Comparisons occur at S64 width before
the low bits are selected, preventing an out-of-range value from silently
wrapping.

### `always_comb` at lines 250–307: command mux

This block translates the current FSM state into requests for workspace, divider,
and square-root resources. Every enable defaults to 0, so an unlisted state is
idle. Request states raise exactly the required enable and its payload together:

| State family | Enable raised | Payload selected |
|---|---|---|
| `P1_REQ`, `P2_REQ`, `P3_REQ` | `ws_rd_en` | Input or scratch row address for the current pass |
| Divider start states | `div_start` | Matching numerator and denominator for mean, fraction, normalization, or quantization |
| `SQRT_START` | `sqrt_start` | `v_raw` already prepared by registered control |
| Pass write states | `ws_wr_en` | Packed scratch or quantized row at `ws_wr_addr` |

Raising an enable requests work; it does not mean the result is immediately
available. The FSM waits for `ws_rd_valid`, divider `done`, or square-root `done`
before advancing. This distinction is why address/data/enable and return-valid
signals must be traced as a bundle.

### Sequential controller at lines 308–555

The large `always_ff` block owns the FSM, counters, accumulated sum, packed rows,
coefficients, and status flags. Reset cancels control and validity. Payload
registers are overwritten before their enabling state consumes them. Each state
either issues a request, waits for its valid/done response, captures a result, or
advances the lane/word counter; the combinational blocks above only prepare the
values for that registered sequence.

### Datapath detail 1

![norm.sv — detail 1](../../diagrams/previews/42_norm.sv_2.svg)

[Editable draw.io — norm.sv — detail 1](../../diagrams/architecture.drawio) · Page `42_norm.sv_2`.

### Datapath detail 2

![norm.sv — detail 2](../../diagrams/previews/43_norm.sv_3.svg)

[Editable draw.io — norm.sv — detail 2](../../diagrams/architecture.drawio) · Page `43_norm.sv_3`.

![norm.sv — detail 3](../../diagrams/previews/44_norm.sv_4.svg)

[Editable draw.io — norm.sv — detail 3](../../diagrams/architecture.drawio) · Page `44_norm.sv_4`.

### Datapath detail 3

![norm.sv — detail 4](../../diagrams/previews/45_norm.sv_5.svg)

[Editable draw.io — norm.sv — detail 4](../../diagrams/architecture.drawio) · Page `45_norm.sv_5`.
