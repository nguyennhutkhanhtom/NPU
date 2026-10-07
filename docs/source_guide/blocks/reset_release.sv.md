# reset_release.sv — Standard-FF reset release boundary

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)

**Source:** [reset_release.sv](<../../../Verilog%20Source%20code/reset_release.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Hai FF chuẩn dùng cùng clock: reset assert bất đồng bộ ngay, release core_rst_n sau hai cạnh lên. Không vendor IP, clock mới, timing exception hay nhánh synthesis. Raw reset chỉ tới hai FF; reset nội bộ tới controller, datapath validity và memory adapters. Storage SRAM không reset. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
    RST[Raw rst_n] --> FF1[First release FF async clear]
    RST --> FF2[Second release FF async clear]
    CLK[clk] --> FF1
    CLK --> FF2
    FF1 --> FF2
    FF2 --> CORE[core_rst_n after two rising edges]
    CORE --> CONTROL[Controller and adapter resets]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

## Important state / datapath groups

### [Dòng 1–6: Reset contract and interface](<../../../Verilog%20Source%20code/reset_release.sv#L1>)

Assert ngay kể cả giữa clock; host phải giữ request đến ready. Reset release không tạo response hay write mới; transaction bắt đầu sau khi core_rst_n lên high.

### [Dòng 7–11: First release register](<../../../Verilog%20Source%20code/reset_release.sv#L7>)

Một always_ff sở hữu release_first_q. Cạnh lên đầu tiên sau rst_n high chỉ chốt one vào FF đầu.

### [Dòng 12–15: Final internal reset register](<../../../Verilog%20Source%20code/reset_release.sv#L12>)

Always_ff thứ hai sở hữu core_rst_n. Cạnh thứ hai chốt one từ FF đầu. Tất cả recovery/removal vẫn được STA; đây không phải ASIC signoff hay bằng chứng MTBF.
