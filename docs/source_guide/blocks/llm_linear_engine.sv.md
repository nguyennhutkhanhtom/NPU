# llm_linear_engine.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_linear_engine.sv](<../../../Verilog%20Source%20code/llm_linear_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | A bounded two-word credit window overlaps parameter reads with four ternary chunks per word. Operands and returned dot sums remain ordered. The engine accumulates S39, faults on reserved code 10, and drains outstanding memory and dot responses on cancellation or fault. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
 S["start_i / ready_o<br/>weight_base_i / chunks_i"] --> C["IDLE / RUN / DRAIN<br/>Request / response / issue / retire counters"]
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
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
