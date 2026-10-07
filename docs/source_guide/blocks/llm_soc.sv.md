# llm_soc

> **Role:** Own autonomous fixed-point inference and route shared resources.
> **Scope:** CURRENT. **Category:** GUIDE.
> **Source:** [llm_soc.sv](<../../../Verilog Source code/llm_soc.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Host transactions, prefill/decode sequencing and ordered operator completion |
| Inputs | Clock/reset; host enable/write/address/data |
| Outputs | Host data/acknowledgement; running/ready/error/overflow; debug signals |
| Owns | Graph/operator/host FSMs, metadata, operand/cache tags, scaling, vector writes, softmax/value passes and token selection |
| Delegates | Linear/head/QK/normalization engines, structural arithmetic and parameter/vector/KV memory adapters |

## Architecture

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
 H["Host request / held acknowledgement<br/>32-bit address and data"] --> F["Registered host frontend<br/>Prompt / configuration / token output"]
 F <--> P["u_parameters<br/>24576 rows x 256 bits"]
 G["Parent graph and operator FSMs<br/>112 one-hot operator bits"] --> R["Parent request and operand muxes"]
 R <--> P
 R <--> V["u_vectors<br/>96 rows x 768 bits"]
 R <--> K["u_cache<br/>4096 rows x 768 bits"]
 G --> L["u_linear_engine<br/>Two-word prefetch / ternary_dot32"]
 G --> E["u_head_engine<br/>Four ordered int8 chunks"]
 G --> A["u_attention_engine<br/>Causal QK scores and maximum"]
 L <-->|"Parameter request / data / valid"| R
 E <-->|"Parameter request / capture / issue"| R
 A <-->|"KV request / capture / issue"| R
 R <--> C["Parent input cache<br/>12 rows x 768 bits"]
 R <--> M["u_math STREAMING=1<br/>32 S24 x S32 lanes"]
 G <--> N["u_attention_normalize<br/>Four lanes: shared + three private dividers"]
 N <-->|"Lane 0 request / quotient / remainder"| D["u_div<br/>RMS reciprocal or attention lane 0"]
 G <--> Q["u_root and four sigmoid instances"]
 G --> O["Parent scaling / sampling<br/>Output token buffer"]
 F -.->|"Launch / status"| G
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

## Main flow

1. Accept host parameters, prompt IDs and configuration; validate START.
2. Select each graph phase and route its memory/arithmetic requests.
3. Consume valid engine responses; finish rounding, saturation and ordered vector writes.
4. Select a token, append its ID and either feed it back or complete generation.

## Important state / datapath groups

| Group | Purpose |
|---|---|
| `graph`, `op` | Phase selection and explicit operator states |
| `layer_q`, `position_q`, `generated_q` | Layer, context position and output progress |
| Input/scale/RoPE tags | Reuse only operands compatible with the next phase |
| `linear_prefetched_q` and retained completion | At most one next row while the current row finishes scalar/store work |
| `temperature_q`, `random_q`, selection score | Greedy or sampled selection; stable ID ordering |

## Important contracts

Linear lookahead preserves ordered accumulator/fault consumption and drains pending work on cancellation. Memory acceptance and write commitment are different events; host acknowledgement follows commitment. Shared-resource muxes are owned here, rather than direct engine-to-engine wiring.

## Easy to misunderstand

- SIMD lanes form one reduction, not independent completed outputs.
- Zero temperature skips noise/sample states but still advances PRNG once per row, including excluded IDs.
- Host supplies prompt/configuration, not hidden activations or continuation IDs.
- The preserved diagram predates row overlap; diagram follow-up is required.

## Related docs

[Architecture/numeric contracts](../../design/full_rtl_language.md) · [Host interface](../../design/host_interface.md) · [Cache contracts](../../design/exact_throughput_optimization.md) · [Full graph module map](../full_graph.md) · [Implementation rationale](../../../review/architecture_optimization_20261007.md)
