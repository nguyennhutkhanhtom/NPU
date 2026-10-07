# postscale.sv — Đổi scale, cộng bias và saturation

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng — postscale_finish sau các register trong ternary_mul; postscale giữ interface tổ hợp cho kiểm tra.

**Source:** [postscale.sv](<../../../Verilog%20Source%20code/postscale.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | File có hai module. `postscale` giữ interface tổ hợp: accumulator S18 nhân hệ số U24, RNE rồi cộng bias và saturation. `postscale_finish` chỉ nhận rounded S42 rồi cộng bias S32/clamp. Ternary engine chốt product và rounded result trước khi gọi module finish; không instantiate toàn chuỗi tổ hợp nữa. |

## Sơ đồ kiến trúc tổng quan

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
 A["Accumulator / scale<br/>S18 × U24"] --> M["Product<br/>S42"]
 M --> R["Signed RNE<br/>Shift U6"]
 R --> F["postscale_finish Bias S43,<br/>saturation and range<br/>flags"]
 B["Bias / output<br/>format S32; S16<br/>or S32 selection"] --> F
 X["Registered rounded result<br/>Alternative ternary_mul caller"] --> F
 F --> O["Result / overflow<br/>S16 or S32"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class A,M,R compute;
class F,B,X,O output;
```

Nét liền là dữ liệu, nét đứt là format/control. Hai module trong file này đều tổ hợp; product/round registers của engine nằm trong [ternary_mul](ternary_mul.sv.md), không nằm trong interface `postscale`.

## Main flow

1. S18×U24 vừa tích S42. M được thêm bit zero trước cast signed để không đổi nghĩa U24.
2. `rne_shift42` giữ thương floor và guard/sticky/parity như RNE S64. Khi r≥42, mọi giá trị S42 làm tròn về zero; S42 min tại r=42 là tie −0,5 và chọn zero chẵn.
3. Rounded S42 cộng bias S32 trong S43, không cắt bit trung gian. Bias đã ở đơn vị output nên cộng sau rounding.
4. `postscale_finish` sign-extend S43 khi gọi hàm saturation chung, đồng thời báo overflow theo format S16/S32 đang chọn.
5. Interface tổ hợp vẫn dùng cho reference regression. Engine gọi `postscale_finish` sau SCALE_PRODUCT → SCALE_ROUND → SCALE, thêm hai clock mỗi output row.

[12.720 ca postscale](../../../tests/results.json) kiểm tra tương đương với reference rộng, gồm shift 0…63, accumulator/M/bias cực trị và clamp. [Timing hub](../../verification/timing/README.md) ghi ảnh hưởng Fmax và chu kỳ model.

## Important state / datapath groups

### [Dòng 1–26: Interface postscale tổ hợp](<../../../Verilog%20Source%20code/postscale.sv#L1>)

**Mục đích.** Wrapper giữ accumulator/M/r/bias ports như trước. Tích S42 được RNE bằng hàm đúng độ rộng; module finish thực hiện cộng bias/clamp. Wrapper không có clock hoặc handshake.

### [Dòng 27–46: Bias adder S43 và saturation dùng chung](<../../../Verilog%20Source%20code/postscale.sv#L27>)

**Mục đích.** Rounded S42 cộng bias S32 trong S43. Hai output được clamp song song; output_s32 chọn miền kiểm tra overflow. Engine registered và wrapper tổ hợp dùng đúng một implementation finish.

#### Sơ đồ khối phần cứng của nhóm

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
    R["Rounded S42<br/>From wrapper or engine register"] --> EXT["Sign extension S43"]
    B["Bias S32, in output units"] --> EXT_B["Sign extension S43"]
    EXT --> ADD["Signed bias adder S43"]
    EXT_B --> ADD
    ADD --> S16["S16 clamp"]
    ADD --> S32["S32 clamp"]
    ADD --> DET["S16 / S32 overflow comparators"]
    F["output_s32"] -.-> DET
    S16 --> Y16["y_s16"]
    S32 --> Y32["y_s32"]
    DET --> OV["overflow"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class R,EXT,EXT_B,DET,Y16,Y32,OV buffer;
class ADD compute;
class B,S16,S32,F output;
```
