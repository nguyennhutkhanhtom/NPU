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
%%{init: {
  "theme": "base",
  "themeVariables": {
    "background": "#ffffff",
    "primaryTextColor": "#111111",
    "secondaryTextColor": "#111111",
    "tertiaryTextColor": "#111111",
    "lineColor": "#444444",
    "clusterBkg": "#ffffff",
    "clusterBorder": "#aaaaaa",
    "edgeLabelBackground": "#ffffff",
    "fontSize": "17px"
  },
  "flowchart": {
    "curve": "linear",
    "nodeSpacing": 30,
    "rankSpacing": 40,
    "htmlLabels": true,
    "useMaxWidth": true
  }
}}%%
flowchart TB
 H["Host<br/>Parameters, prompt and config"] <--> F["Host frontend<br/>Requests, ACK and output IDs"]
 subgraph PARENT["llm_soc ownership"]
  C["Graph / operator FSMs<br/>Phase and resource ownership"]
  O["Operand / metadata caches<br/>Validity and reuse tags"]
  S["Scalar / vector processing<br/>Round, clamp and store"]
  T["Token selection<br/>Greedy or sampled"]
 end
 F -.-> C
 C -.-> O & S & T
 O --> E["Operator engines<br/>Linear / head / QK / normalize"]
 E --> S
 S --> T
 T --> F
 B["Shared resource ports<br/>Memory / arithmetic adapters"] <--> E
 O --> B
 S --> B
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
style PARENT fill:#ffffff,stroke:#aaaaaa,color:#111111;
class C control;
class H,F,B interface;
class O buffer;
class E compute;
class S,T output;
```

```mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "background": "#ffffff",
    "primaryTextColor": "#111111",
    "secondaryTextColor": "#111111",
    "tertiaryTextColor": "#111111",
    "lineColor": "#444444",
    "clusterBkg": "#ffffff",
    "clusterBorder": "#aaaaaa",
    "edgeLabelBackground": "#ffffff",
    "fontSize": "17px"
  },
  "flowchart": {
    "curve": "linear",
    "nodeSpacing": 30,
    "rankSpacing": 40,
    "htmlLabels": true,
    "useMaxWidth": true
  }
}}%%
flowchart TB
 subgraph ROW["Ordered linear row processing"]
  L["Linear engine<br/>One active row"] --> R["Retained completion<br/>S39 accumulator + fault"]
  R --> W["Parent row wait<br/>Consume result once"]
  W --> S["Scalar pipeline<br/>Coefficient, RNE and clamp"]
  S --> V["Vector store<br/>Current row output"]
 end
 C["Row launch control<br/>At most one lookahead"] -.-> L
 S -.->|"launch next row"| C
 V ==>|"advance row"| W
 F["Reset / launch / fault<br/>Cancel or invalidate"] -.-> C & R
 P["Parameter / operand ports<br/>Parent-owned routing"] --> L
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
style ROW fill:#ffffff,stroke:#aaaaaa,color:#111111;
class C,W,F control;
class P interface;
class R buffer;
class L compute;
class S,V output;
```

```mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "background": "#ffffff",
    "primaryTextColor": "#111111",
    "secondaryTextColor": "#111111",
    "tertiaryTextColor": "#111111",
    "lineColor": "#444444",
    "clusterBkg": "#ffffff",
    "clusterBorder": "#aaaaaa",
    "edgeLabelBackground": "#ffffff",
    "fontSize": "17px"
  },
  "flowchart": {
    "curve": "linear",
    "nodeSpacing": 30,
    "rankSpacing": 40,
    "htmlLabels": true,
    "useMaxWidth": true
  }
}}%%
flowchart TB
 R["Head row result<br/>Coefficient product + RNE24"] --> T{"Temperature zero?"}
 T -->|"yes"| G["Greedy score<br/>Advance PRNG once"]
 T -->|"no"| N["Gumbel score<br/>Add noise; advance PRNG once"]
 G --> S["Score clamp / eligibility<br/>Stable lowest-ID tie"]
 N --> S
 S --> B["Best token state<br/>Eligible updates only"]
 B ==>|"next vocabulary row"| R
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class T control;
class R,G,N,S,B output;
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
| `linear_active_q`, `linear_row_issue_q`, `linear_pipe_valid_q/linear_pipe_row_q` | One matrix stream; ordered engine results feed the existing scalar registers with stage validity and aligned row tags |
| `temperature_q`, `random_q`, selection score | Greedy or sampled selection; stable ID ordering |

## Important contracts

Linear execution launches once in `L_ROW_START` and remains in `L_ROW_WAIT` while the engine issues consecutive rows. Its bounded result FIFO feeds coefficient multiplication, RNE, saturation and lane packing through the existing registers. The final lane is captured before the tagged bank write is accepted; a write may overlap packing the next bank. Fault consumption waits for older scalar packets to finish, then drains accepted memory/dot work. Completion waits for empty row results, scalar validity and bank write queues. Memory acceptance and write commitment are different events; host acknowledgement follows commitment. Shared-resource muxes are owned here, rather than direct engine-to-engine wiring.

Diagram follow-up required: the existing ordered-linear diagram still depicts one-row lookahead and FSM-driven epilogue serialization.

## Easy to misunderstand

- SIMD lanes form one reduction, not independent completed outputs.
- Zero temperature skips noise/sample states but still advances PRNG once per row, including excluded IDs.
- Host supplies prompt/configuration, not hidden activations or continuation IDs.
- Result slots include queued sums and rows already issued into the dot pipeline. Backpressure retains the oldest sum/fault pair and bounds further row issue.

## Related docs

[Architecture/numeric contracts](../../design/full_rtl_language.md) · [Host interface](../../design/host_interface.md) · [Cache contracts](../../design/exact_throughput_optimization.md) · [Full graph module map](../full_graph.md) · [Implementation rationale](../../../review/architecture_optimization_20261007.md)
