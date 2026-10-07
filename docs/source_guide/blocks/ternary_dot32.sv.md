# ternary_dot32.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [ternary_dot32.sv](<../../../Verilog%20Source%20code/ternary_dot32.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Thirty-two signed S24 operands multiply ternary codes through S25 sign extension, zero selection and negation. Code 10 produces an aligned reserved flag. Four registered stages implement S25 terms, S28 octets, S29 halves and S30 sum; intervening pair/quad adders are combinational. Throughput is one transaction per cycle. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart LR
 X["32 S24 operands"] --> E["S25 sign extension"]
 W["32 U2 codes<br/>01 plus / 11 minus / 00 zero"] --> T["Registered S25 terms"]
 E --> T
 T --> P["Combinational S26 pairs<br/>Combinational S27 quads"]
 P --> O["Registered S28 octets"]
 O --> H["Registered S29 halves"]
 H --> S["Registered S30 sum_o"]
 W --> F["Code 10 detector<br/>Four-stage reserved / valid pipeline"]
 F --> V["valid_o / reserved_o"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
