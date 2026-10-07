# llm_math.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_math.sv](<../../../Verilog%20Source%20code/llm_math.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Thirty-two S24 by S32 lanes use four structural byte multipliers per lane. Captured operands feed continuously clocked product/reduction stages. STREAMING=1 accepts every cycle while reset is released; STREAMING=0 admits one outstanding transaction. Relative to acceptance E0, product_valid is E3, sum_valid E8 and legacy done E9. |

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
 I["Input handshake<br/>32 S24 / S32 pairs"] --> C["Captured operands<br/>Acceptance E0"]
 C --> M["Byte-product pipeline<br/>128 structural multipliers"]
 M --> P["Lane products<br/>32 S56 values at E3"]
 P --> R["Registered reduction<br/>S61 sum at E8"]
 V["Valid / ready control<br/>STREAMING mode"] -.-> C & P & R
 V -.-> D["Legacy completion<br/>Done at E9"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class I interface;
class C buffer;
class M,R compute;
class P,D output;
class V control;
```

## Internal arithmetic pipeline

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
 B["Byte multipliers<br/>Three unsigned; one signed"] --> P["Partial products<br/>S33 at E1"]
 P --> R["Pair sums<br/>S41 at E2"]
 R --> X["Lane product<br/>S56 at E3"]
 X --> T["Five reduction stages<br/>S57 → S61"]
 T --> O["Sum<br/>S61 at E8"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class B,T compute;
class P,R buffer;
class X,O output;
```
