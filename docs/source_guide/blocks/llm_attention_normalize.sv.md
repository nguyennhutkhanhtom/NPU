# llm_attention_normalize.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_attention_normalize.sv](<../../../Verilog%20Source%20code/llm_attention_normalize.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Normalize 32 signed accumulators in batches of DIV_LANES. In llm_soc, DIV_LANES=4 and USE_SHARED=1: lane zero is wired to top u_div and lanes one through three instantiate private dividers. Quotient/remainder capture, RNE, sign restoration and S24 clamp occupy separate stages. Standalone USE_SHARED=0 instantiates all dividers internally. |

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
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class B,S,N,O buffer;
class A,P,Q,R compute;
class C output;
class L platform;
```
