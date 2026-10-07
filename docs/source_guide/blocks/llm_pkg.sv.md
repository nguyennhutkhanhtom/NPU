# llm_pkg.sv — Layout, saturation và sampler

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)

**Source:** [llm_pkg.sv](<../../../Verilog%20Source%20code/llm_pkg.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Hằng số graph cố định NanoFable, địa chỉ parameter rows, S24 saturation, sign extension và xorshift32. LUT exp/Gumbel được include thành logic portable. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
    LAYOUT[Fixed graph and SRAM offsets] --> CTRL[llm_soc]
    SAT[S24 saturation and S56 extension] --> MATH[Numeric datapath]
    EXP[Exponential LUT] --> ATT[Softmax]
    RANDOM[Xorshift32 and Gumbel LUT] --> HEAD[Token selection]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

## Important state / datapath groups

### [Dòng 1–10: Layout constants](<../../../Verilog%20Source%20code/llm_pkg.sv#L1>)

PARAM_ROWS=24576; địa chỉ tính theo row 256 bit. EMB_SCALE, matrix metadata, gains và RoPE nằm sau trọng số.

### [Dòng 11–20: Numeric helpers](<../../../Verilog%20Source%20code/llm_pkg.sv#L11>)

Saturation ở biên ±2^23; llm_extend56 giữ sign của SIMD product trước RNE64.

### [Dòng 21–31: Sampler](<../../../Verilog%20Source%20code/llm_pkg.sv#L21>)

Xorshift32 deterministic, seed zero được controller thay bằng one. Temperature zero cho greedy argmax.
