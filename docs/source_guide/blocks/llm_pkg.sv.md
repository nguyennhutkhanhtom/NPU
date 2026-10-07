# llm_pkg.sv — Layout, saturation và sampler

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)

**Source:** [llm_pkg.sv](<../../../Verilog%20Source%20code/llm_pkg.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Hằng số graph cố định NanoFable, địa chỉ parameter rows, S24 saturation, sign extension và xorshift32. LUT exp/Gumbel được include thành logic portable. |

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
    LAYOUT["Fixed graph and SRAM offsets"] --> CTRL["llm_soc"]
    SAT["S24 saturation and<br/>S56 extension"] --> MATH["Numeric datapath"]
    EXP["Exponential LUT"] --> ATT["Softmax"]
    RANDOM["Xorshift32 and Gumbel LUT"] --> HEAD["Token selection"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class LAYOUT platform;
class CTRL,MATH buffer;
class SAT,HEAD output;
class EXP,ATT,RANDOM compute;
```

## Important state / datapath groups

### [Dòng 1–10: Layout constants](<../../../Verilog%20Source%20code/llm_pkg.sv#L1>)

PARAM_ROWS=24576; địa chỉ tính theo row 256 bit. EMB_SCALE, matrix metadata, gains và RoPE nằm sau trọng số.

### [Dòng 11–20: Numeric helpers](<../../../Verilog%20Source%20code/llm_pkg.sv#L11>)

Saturation ở biên ±2^23; llm_extend56 giữ sign của SIMD product trước RNE64.

### [Dòng 21–31: Sampler](<../../../Verilog%20Source%20code/llm_pkg.sv#L21>)

Xorshift32 deterministic, seed zero được controller thay bằng one. Temperature zero cho greedy argmax.
