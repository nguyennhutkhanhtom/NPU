# scale_compose.sv — Ghép scale bằng lựa chọn shift song song

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Source guide](<../legacy/README.md>) → [Mục lục](README.md)

**Source:** [scale_compose.sv](<../../../Verilog%20Source%20code/scale_compose.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Ghép factor_m/factor_r với quant_d thành result_m U24 và result_r U6. Chốt tích U48, đánh giá song song 48 threshold hằng, chọn shift lớn nhất còn vừa U24, rồi thực hiện một divider U48/U25 và RNE. Không còn vòng decrement candidate. |

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
    IN["U24 factors and U6 base shift"] --> MUL["Registered U48 product"]
    MUL --> FIT["48 constant threshold<br/>comparisons"]
    FIT --> SELECT["Prefix boundary and<br/>signed target shift"]
    SELECT --> SHIFT["Registered numerator and<br/>denominator"]
    SHIFT --> DIV["Divider U48 by U25"]
    DIV --> RNE["Remainder RNE and range checks"]
    SELECT --> OUT["Result M and r"]
    RNE --> OUT
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class IN,SELECT,DIV,RNE compute;
class MUL,FIT,SHIFT buffer;
class OUT output;
```

## Important state / datapath groups

### [Dòng 1–29: Interface and state](<../../../Verilog%20Source%20code/scale_compose.sv#L1>)

Valid factors dùng factor_r≤47 và quant_d khác zero. factor_m=0 trả zero hợp lệ. Control dùng MULTIPLY, SELECT_SHIFT và SHIFT trước DIV_START.

### [Dòng 30–53: Parallel threshold selection](<../../../Verilog%20Source%20code/scale_compose.sv#L30>)

positive_fit là prefix ones. COEFFICIENT_LIMIT=0x7EFF_FFC0_8000; strict inequality loại tie U24_max+1/2. Boundary encoder chọn shift mà không tạo chuỗi decrement.

### [Dòng 54–67: Registered multiplication and shift](<../../../Verilog%20Source%20code/scale_compose.sv#L54>)

Multiply không asynchronous reset; control bảo đảm capture trước use. Shift âm tối thiểu −2, nên denominator không vượt U25.

### [Dòng 68–76: Divider](<../../../Verilog%20Source%20code/scale_compose.sv#L68>)

Một lần chia 48 bước. Quotient U48, remainder U25; twice_rem U26 và rounded U49 giữ carry để RNE ties-even.

### [Dòng 77–116: Launch and selection control](<../../../Verilog%20Source%20code/scale_compose.sv#L77>)

Target r=base_r+selected_shift. Nếu target>47, clamp r về47 và điều chỉnh shift; target âm hoặc input sai báo format_error.

### [Dòng 117–154: Result and completion](<../../../Verilog%20Source%20code/scale_compose.sv#L117>)

DIV_WAIT kiểm tra zero, underflow và range; kết quả vượt U24 không thể xuất hiện khi selector đúng. Unit regression ghi compose_max_clocks=54.
