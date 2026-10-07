# norm.sv

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [norm.sv](<../../../Verilog%20Source%20code/norm.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Legacy three-pass RMS normalization and quantization. Two shared structural multipliers, one divider and the separately defined isqrt_u64 serve the explicit pass controller. Workspace scratch and final quantized values are packed in 256-bit words. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
WS@{ shape: rect, label: "Workspace SRAM<hr/>X S16 · scratch S32 · q S8" }
    CFG["Descriptors / epsilon / delta / start"]
    subgraph CORE["norm — shared arithmetic datapath"]
        CTRL["Controller / bounds / row-lane counters"]
        READ["Read buffer 256 bit + two-lane selectors"]
        OPS@{ shape: trap-t, label: "Operand mux by pass<hr/>P1: X × X<hr/>P2: X × M_norm<hr/>P3: z × M_quant" }
        OREG["Operand + shift registers<br/>Two S25 pairs · U6 shift"]
        MUL["Two signed 25 × 25 multipliers<br/>Product S48"]
        PREG["Product registers<br/>2 × S48"]
        RNE["Two shared RNE paths<br/>Shift 0 / norm_r / quant_r"]
        RREG["Rounded result registers<br/>2 × S64"]
        SUM["P1: tail mask + pair sum<br/>Accumulator U40"]
        COEF["Shared internal div 55/32<br/>isqrt_u64 / coefficient RNE"]
        Z["P2: clamp S24/F16<br/>abs + max tracker"]
        Q["P3: clamp S8"]
        PACK["Output packer 256 bit<br/>Scratch S32 or q S8"]
    end
    CFG -.-> CTRL
    CFG -.-> COEF
    CTRL -.->|"Read/write"| WS
    WS --> READ
    READ --> OPS
    CTRL -.->|"Pass selection"| OPS
    COEF -.->|"M/r"| OPS
    OPS --> OREG
    OREG --> MUL
    MUL --> PREG
    PREG --> SUM
    PREG --> RNE
    COEF -.->|"r"| RNE
    SUM --> COEF
    RNE --> RREG
    RREG --> Z
    RREG --> Q
    Z -->|"D=max(absmax,delta)"| COEF
    Z --> PACK
    Q --> PACK
    PACK --> WS
    COEF --> META["norm M/r · quant M/r · D"]
    CTRL -.-> STATUS["busy / done / overflow / format_error"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

## Main flow

### Datapath detail 1

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
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
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

### Datapath detail 2

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
X["Read buffer<br/>Two X values S16"] --> OREG["P2_CAPTURE<br/>Operand S25 / shift U6 registers"]
    COEF["norm_m U24 / norm_r U6"] --> OREG
    OREG --> MUL["Two shared multipliers in P2<br/>X × norm_m"]
    MUL --> PREG["P2_MUL<br/>Product registers S48"]
    PREG --> RNE["Shared RNE paths"]
    OREG -.->|"Shift"| RNE
    RNE --> RREG["P2_ROUND<br/>Rounded registers S64"]
    RREG --> ROUND["S24 clamp"]
    ROUND --> PACK["Sign-extension to S32<br/>256-bit scratch pack buffer"]
    ROUND --> MAX["Absolute-value + max comparator<br/>absmax storage"]
    PACK --> WS["Workspace scratch write port"]
    MAX --> D@{ shape: trap-t, label: "D selector / quantization coefficient block" }
    CTRL["Address / lane / pack counters + write control"] -.-> PACK
    CTRL -.-> WS
    ROUND -.-> OV["Overflow aggregation"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

### Datapath detail 3

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
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
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
