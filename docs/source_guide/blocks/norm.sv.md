# norm.sv

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [norm.sv](<../../../Verilog%20Source%20code/norm.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Legacy three-pass RMS normalization and quantization. Two shared structural multipliers, one divider and the separately defined isqrt_u64 serve the explicit pass controller. Workspace scratch and final quantized values are packed in 256-bit words. |

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
 I["Workspace / descriptors<br/>256-bit words"] --> B["Input buffer / lane selection"]
 subgraph CORE["Legacy norm datapath"]
  C["Three-pass control Bounds<br/>and tail masks"]
  M["Shared multiply /<br/>RNE pipeline Two<br/>arithmetic lanes"]
  P1["Pass 1 Square<br/>sum and coefficient"]
  P2["Pass 2 Normalized<br/>S24 and maximum"]
  P3["Pass 3<br/>Quantized S8"]
 end
 B --> M
 M --> P1 & P2 & P3
 C -.-> M
 P1 -.-> P2
 P2 -.-> P3
 P2 --> O["Output packer Scratch<br/>S32 / quantized<br/>S8"]
 P3 --> O
 O --> W["Workspace write 256-bit<br/>words"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class C control;
class W interface;
class I,B,P3 buffer;
class M,P1 compute;
class P2,O output;
style CORE fill:#ffffff,stroke:#aaaaaa,color:#111111;
```

## Main flow

### Datapath detail 1

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
WS["Workspace read port 256 bit"] --> BUF["Read buffer + two S16 lane selectors"]
    CTRL["Word/lane counters + length mask<br/>Read request controller"] -.-> WS
    CTRL -.-> BUF
    BUF --> SQ0["Shared multiplier 0 in P1<br/>S16 × S16"]
    BUF --> SQ1["Shared multiplier 1 in P1<br/>S16 × S16"]
    SQ0 --> MASK["Tail mask + pair sum U40"]
    SQ1 --> MASK
    CTRL -.-> MASK
    MASK --> ACC["U40 sum accumulator<br/>Adder + sum_sq storage"]
    ACC --> COEF["Mean-square / coefficient block"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class CTRL control;
class WS interface;
class BUF,MASK buffer;
class SQ0,SQ1,ACC,COEF compute;
```

### Datapath detail 2

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
 X["Input buffer<br/>Two S16 values"] --> O["Captured operands<br/>S25 and U6 shift"]
 C["Norm coefficient<br/>U24 M / U6 r"] --> O
 O --> M["Shared multipliers<br/>S48 product at P2_MUL"]
 M --> R["Shared RNE<br/>S64 result at P2_ROUND"]
 O -.-> R
 R --> S["S24 clamp<br/>Normalized values / overflow"]
 S --> P["Scratch packer<br/>S32 slots in 256-bit words"]
 P --> W["Workspace write port"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class X,O,C buffer;
class M,R compute;
class S,P output;
class W interface;
```

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
flowchart LR
 S["Normalized S24 values"] --> A["Absolute value / maximum"]
 A --> M["absmax storage"]
 M --> D["D selection<br/>Quantization coefficient"]
 C["Address / lane / pack control"] -.-> M
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class S interface;
class A,D compute;
class M buffer;
class C control;
```

### Datapath detail 3

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
WS["Workspace scratch read port<br/>256 bit = 8 S32 slots"] --> BUF@{ shape: trap-t, label: "Read buffer + two S24 lane selectors" }
    BUF --> OREG["P3_CAPTURE<br/>Operand S25 / shift U6 registers"]
    COEF["quant_m U24 / quant_r U6"] --> OREG
    OREG --> MUL["Two shared multipliers in P3<br/>z × quant_m"]
    MUL --> PREG["P3_MUL<br/>Product registers S48"]
    PREG --> RNE["Shared RNE paths"]
    OREG -.->|"Shift"| RNE
    RNE --> RREG["P3_ROUND<br/>Rounded registers S64"]
    RREG --> ROUND["S8 clamp"]
    ROUND --> PACK["256-bit output pack buffer<br/>32 q values S8"]
    PACK --> OUT["Workspace q write port"]
    CTRL["Read/write controller<br/>Address / lane / pack counters"] -.-> WS
    CTRL -.-> BUF
    CTRL -.-> PACK
    CTRL -.-> OUT
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class CTRL control;
class WS,OUT interface;
class OREG,COEF,PREG,RREG,BUF buffer;
class MUL,RNE compute;
class ROUND,PACK output;
```
