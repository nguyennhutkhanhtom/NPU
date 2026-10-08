# postscale.sv — Đổi scale, cộng bias và saturation

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng — postscale_finish sau các register trong ternary_mul; postscale giữ interface tổ hợp cho kiểm tra.

**Source:** [postscale.sv](<../../../Verilog%20Source%20code/postscale.sv>).

Input ports khai báo rõ `wire logic` dưới `default_nettype none` để Xcelium
không phải suy luận net type (NODNTW). Width/signedness và arithmetic giữ nguyên.

## At a glance

| Item | Description |
|---|---|
| Responsibility | File có hai module. `postscale` giữ interface tổ hợp: accumulator S18 nhân hệ số U24, RNE rồi cộng bias và saturation. `postscale_finish` chỉ nhận rounded S42 rồi cộng bias S32/clamp. Ternary engine chốt product và rounded result trước khi gọi module finish; không instantiate toàn chuỗi tổ hợp nữa. |

## Sơ đồ kiến trúc tổng quan

![postscale.sv — overview](../../diagrams/previews/51_postscale.sv_1.svg)

[Editable draw.io — postscale.sv — overview](../../diagrams/architecture.drawio) · Page `51_postscale.sv_1`.

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

![postscale.sv — detail 1](../../diagrams/previews/52_postscale.sv_2.svg)

[Editable draw.io — postscale.sv — detail 1](../../diagrams/architecture.drawio) · Page `52_postscale.sv_2`.
