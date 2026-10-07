# llm_math.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_math.sv](<../../../Verilog%20Source%20code/llm_math.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Thirty-two S24 by S32 lanes use four structural byte multipliers per lane. Captured operands feed continuously clocked product/reduction stages. STREAMING=1 accepts every cycle while reset is released; STREAMING=0 admits one outstanding transaction. Relative to acceptance E0, product_valid is E3, sum_valid E8 and legacy done E9. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart LR
 I["start AND in_ready<br/>32 S24 / S32 operand pairs at E0"] --> C["Operand registers"]
 C --> B["128 logic_mul instances<br/>Three unsigned bytes / one signed byte per lane"]
 B --> P["Partial registers S33 at E1"]
 P --> R["Pair registers S41 at E2"]
 R --> X["Product registers S56 at E3"]
 X --> T["Five registered reduction levels<br/>S57 / S58 / S59 / S60 / S61"]
 T --> S["sum S61 at E8"]
 V["10-bit valid pipeline<br/>Reset cancels validity"] -.->|"product_valid E3"| X
 V -.->|"sum_valid E8"| S
 V --> D["busy / done E9<br/>in_ready depends on STREAMING"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
