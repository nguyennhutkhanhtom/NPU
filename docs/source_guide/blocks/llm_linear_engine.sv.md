# llm_linear_engine.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_linear_engine.sv](<../../../Verilog%20Source%20code/llm_linear_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | A bounded two-word credit window overlaps parameter reads with four ternary chunks per word. Operands and returned dot sums remain ordered. The engine accumulates S39, faults on reserved code 10, and drains outstanding memory and dot responses on cancellation or fault. |

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
 S["start_i / ready_o<br/>weight_base_i / chunks_i"] --> C["IDLE / RUN / DRAIN<br/>Request / response / issue<br/>/ retire counters"]
 C --> Q["Parameter request credit<br/>At most two unconsumed words"]
 Q --> P["Parent parameter SRAM mux"]
 P -->|"parameter_data_i / parameter_valid_i"| F["Two entries x 256-bit FIFO"]
 F --> W["Four 64-bit weight chunks per word"]
 X["Parent cached S24 operands<br/>input_chunk_o selects 32 lanes"] --> R["Operand registers x_q / w_q"]
 W --> R
 R --> D["u_dot<br/>(ternary_dot32)"]
 D -->|"valid_o / sum_o S30"| A["Ordered S39 accumulator"]
 D -.->|"reserved_o"| C
 C --> O["done_o / fault_o / busy_o"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class C control;
class Q interface;
class S,F,W,X,R,O buffer;
class D,A compute;
class P platform;
```
