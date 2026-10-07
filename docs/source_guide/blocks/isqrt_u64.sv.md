# isqrt_u64.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [isqrt_u64.sv](<../../../Verilog%20Source%20code/isqrt_u64.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Unsigned floor square root with 32 radix-four iterations. Append two radicand bits per step; one U35 subtractor supplies the trial remainder and borrow decision. Root and remainder feedback are explicit registers. start is accepted only when idle; busy/done frame the result. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
 I["start / U64 radicand"] --> R["Radicand work register<br/>Shift left by two per step"]
 R --> A["Append next two bits<br/>U34 remainder_shift"]
 M["U34 remainder register"] --> A
 Q["U32 root register"] --> T["Trial: root shifted left two OR 1"]
 A --> S["U35 subtractor<br/>Borrow selects acceptance"]
 T --> S
 S --> M
 S --> Q
 C["Controller / 32-step counter"] -.-> R
 C -.-> Q
 C -.-> M
 Q --> O["root U32 / busy / done"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
