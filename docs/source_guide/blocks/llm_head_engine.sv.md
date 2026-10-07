# llm_head_engine.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_head_engine.sv](<../../../Verilog%20Source%20code/llm_head_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Issue four ordered parameter reads for a vocabulary row, request parent operand capture and shared SIMD issue, then accumulate four sum_valid responses into S39. The parent owns row-scale caching, RNE, PRNG order and token selection. |

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
 S["start_i / vocabulary_i"] --> C["Active flag<br/>Request / response / sum counters"]
 C --> P["Four parameter addresses<br/>vocabulary row x 4 + chunk"]
 P --> M["Parent parameter SRAM"]
 M -->|"parameter_valid_i"| O["operand_capture_o / input_chunk_o"]
 O --> R["Parent operand registers"]
 R --> Q["math_issue_o on following edge"]
 Q --> SIMD["Parent shared u_math"]
 SIMD -->|"sum_valid_i / sum_i"| A["S39 accumulator<br/>done_o after fourth sum"]
 A --> OUT["Parent row scale / sampling"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class C control;
class S,O,R,Q,SIMD buffer;
class P,A,OUT compute;
class M platform;
```
