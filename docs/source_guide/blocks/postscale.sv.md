# postscale.sv — Đổi scale, cộng bias và saturation

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng — postscale_finish sau các register trong ternary_mul; postscale giữ interface tổ hợp cho kiểm tra.

**Source:** [postscale.sv](<../../../Verilog%20Source%20code/postscale.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | File có hai module. `postscale` giữ interface tổ hợp: accumulator S18 nhân hệ số U24, RNE rồi cộng bias và saturation. `postscale_finish` chỉ nhận rounded S42 rồi cộng bias S32/clamp. Ternary engine chốt product và rounded result trước khi gọi module finish; không instantiate toàn chuỗi tổ hợp nữa. |

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
A["acc S18"] --> MUL["Multiplier<br/>S18 × U24 → S42"]
    M["scale_m U24"] --> MUL
    MUL --> RNE["rne_shift42<br/>Signed RNE S42"]
    R["scale_r U6"] -.-> RNE
    subgraph FIN["postscale_finish — reused combinational module"]
        ADD["Bias adder S43"]
        S16["Saturation S16"]
        S32["Saturation S32"]
        DET["S16 / S32 range detectors"]
    end
    RNE --> ADD
    B["bias S32 sign-extended"] --> ADD
    ADD --> S16
    ADD --> S32
    ADD --> DET
    F["output_s32"] -.-> DET
    S16 --> Y16["y_s16"]
    S32 --> Y32["y_s32"]
    DET --> OV["overflow"]
    REG["ternary_mul rounded register S42<br/>Alternative caller"] --> ADD
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
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
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
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
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
