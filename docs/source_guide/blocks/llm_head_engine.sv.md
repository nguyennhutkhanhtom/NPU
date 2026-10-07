# llm_head_engine.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_head_engine.sv](<../../../Verilog%20Source%20code/llm_head_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Issue four ordered parameter reads for a vocabulary row, request parent operand capture and shared SIMD issue, then accumulate four sum_valid responses into S39. The parent owns row-scale caching, RNE, PRNG order and token selection. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
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
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
