# reset_release.sv — Standard-FF reset release boundary

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)

**Source:** [reset_release.sv](<../../../Verilog%20Source%20code/reset_release.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Hai FF chuẩn dùng cùng clock: reset assert bất đồng bộ ngay, release core_rst_n sau hai cạnh lên. Không vendor IP, clock mới, timing exception hay nhánh synthesis. Raw reset chỉ tới hai FF; reset nội bộ tới controller, datapath validity và memory adapters. Storage SRAM không reset. |

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
    RST["Raw rst_n"] --> FF1["First release FF async clear"]
    RST --> FF2["Second release FF async clear"]
    CLK["clk"] --> FF1
    CLK -.-> FF2
    FF1 --> FF2
    FF2 --> CORE["core_rst_n after two<br/>rising edges"]
    CORE --> CONTROL["Controller and adapter resets"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class RST,FF1,FF2,CLK,CORE buffer;
class CONTROL control;
```

## Important state / datapath groups

### [Dòng 1–6: Reset contract and interface](<../../../Verilog%20Source%20code/reset_release.sv#L1>)

Assert ngay kể cả giữa clock; host phải giữ request đến ready. Reset release không tạo response hay write mới; transaction bắt đầu sau khi core_rst_n lên high.

### [Dòng 7–11: First release register](<../../../Verilog%20Source%20code/reset_release.sv#L7>)

Một always_ff sở hữu release_first_q. Cạnh lên đầu tiên sau rst_n high chỉ chốt one vào FF đầu.

### [Dòng 12–15: Final internal reset register](<../../../Verilog%20Source%20code/reset_release.sv#L12>)

Always_ff thứ hai sở hữu core_rst_n. Cạnh thứ hai chốt one từ FF đầu. Tất cả recovery/removal vẫn được STA; đây không phải ASIC signoff hay bằng chứng MTBF.
