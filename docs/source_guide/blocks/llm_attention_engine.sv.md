# llm_attention_engine.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_attention_engine.sv](<../../../Verilog%20Source%20code/llm_attention_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Issue ordered K-cache reads for positions zero through the current causal position. The parent captures Q/K operands and issues shared SIMD operations. Each sum is rounded by RNE16, narrowed to S39, structurally multiplied by 11585, then rounded by RNE16 and clamped to S32. The engine owns 128 scores and the running maximum; softmax and value accumulation stay in the parent. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
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
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
