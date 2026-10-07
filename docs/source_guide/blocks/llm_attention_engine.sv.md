# llm_attention_engine.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_attention_engine.sv](<../../../Verilog%20Source%20code/llm_attention_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Issue ordered K-cache reads for positions zero through the current causal position. The parent captures Q/K operands and issues shared SIMD operations. Each sum is rounded by RNE16, narrowed to S39, structurally multiplied by 11585, then rounded by RNE16 and clamped to S32. The engine owns 128 scores and the running maximum; softmax and value accumulation stay in the parent. |

## Sơ đồ kiến trúc

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
 C["start_i / layer_i / head_i / position_i"] --> Q["Ordered causal KV requests<br/>0 through position_i"]
 Q --> K["Parent KV SRAM"]
 K -->|"kv_valid_i"| O["operand_capture_o<br/>Parent Q/K operand registers"]
 O --> M["math_issue_o<br/>Parent shared u_math"]
 M -->|"sum_i / sum_valid_i"| R["RNE16 and S39 register"]
 R --> S["u_scale logic_mul<br/>S39 x 11585 to S55"]
 S --> T["Registered product<br/>RNE16 and S32 clamp"]
 T --> A["128-entry score array<br/>Maximum comparator / register"]
 A --> OUT["score_o / max_score_o / done_o<br/>Parent softmax and V pass"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class Q interface;
class C,O,M,R,A buffer;
class S,OUT compute;
class T output;
class K platform;
```
