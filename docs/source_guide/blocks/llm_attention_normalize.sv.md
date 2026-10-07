# llm_attention_normalize.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_attention_normalize.sv](<../../../Verilog%20Source%20code/llm_attention_normalize.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Normalize 32 signed accumulators in batches of DIV_LANES. In llm_soc, DIV_LANES=4 and USE_SHARED=1: lane zero is wired to top u_div and lanes one through three instantiate private dividers. Quotient/remainder capture, RNE, sign restoration and S24 clamp occupy separate stages. Standalone USE_SHARED=0 instantiates all dividers internally. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
 A["32 signed S56 accumulators<br/>Shared U32 denominator"] --> B["Batch operand capture<br/>Magnitude U64 / sign bits"]
 B --> L["Lane 0 external u_div<br/>USE_SHARED=1 in llm_soc"]
 B --> P["Lanes 1 to 3 private dividers<br/>U64 numerator / U32 denominator"]
 L --> Q["Capture quotient and RNE decision"]
 P --> Q
 Q --> R["ROUND<br/>Increment ties to even"]
 R --> S["SIGN<br/>Restore original sign"]
 S --> C["CLAMP<br/>S24 output lane registers"]
 C --> N["NEXT_BATCH<br/>Eight batches at four lanes"]
 N -->|"More lanes"| B
 N --> O["vector_o 768 bits / done_o"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
