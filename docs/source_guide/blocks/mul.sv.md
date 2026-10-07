# mul.sv — Helper nhân S16 và gate

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Helper — không instantiate trong top hiện tại.

**Source:** [mul.sv](<../../../Verilog%20Source%20code/mul.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Helper nhân a signed 16 với b signed 16 hoặc unsigned gate. Rowwise_op đã có đường nhân chia sẻ MUL/REC riêng; không cộng helper này vào số multiplier của top. |

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
 A["Operand A<br/>S16"] --> M["Signed multiply<br/>S16 × S17 → S33"]
 B["Operand B<br/>16-bit signed / unsigned"] --> E["Sign / zero extension"]
 E --> M
 M --> P["Raw product<br/>Low 32 bits"]
 M --> R["Scale / RNE<br/>Sign-extended S64"]
 R --> S["S16 saturation<br/>Result and overflow"]
 B -.-> G["Unsigned gate range<br/>Check above 0x8000"]
 G -.-> S
 C["Unsigned mode / rshift"] -.-> E & R & G
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class A,B interface;
class E buffer;
class M,R compute;
class P,S output;
class C,G control;
```

## Main flow

b_s17 giữ đúng sign hoặc zero-extend gate. Tích p33 được RNE theo rshift rồi clamp S16. product chỉ xuất32 bit thấp của p33. Gate unsigned vượt raw `0x8000` bị báo overflow; không nên dùng helper như multiplier U16 tổng quát không giới hạn.

1. A luôn là S16. B được sign-extend nếu signed hoặc zero-extend nếu là gate U16.
2. Tích S33 giữ trường hợp S16×0x8000; `product` chỉ xuất 32 bit thấp vì interface helper cũ.
3. Đường result mở rộng lên S64, RNE theo rshift rồi clamp S16.
4. Gate trên raw 0x8000 bị báo overflow vì ngoài miền 0…1 của U16/F15.
5. Helper không được top instantiate; rowwise_op có đường multiplier/scale hoàn chỉnh hơn.

## Important state / datapath groups

### [Dòng 1–15: Giao diện và intermediate](<../../../Verilog%20Source%20code/mul.sv#L1>)

**Mục đích.** b_unsigned quyết định cách diễn giải cùng16 bit của b.

**Cách phần code hoạt động.** Nhóm này định nghĩa giao diện, độ rộng, kiểu hoặc tín hiệu trung gian. Nó tạo cấu trúc để các nhóm xử lý sau sử dụng, chưa tự biểu diễn một bước runtime riêng.

**Tín hiệu và dữ liệu chính.** `a`: operand A; `b`: operand B; `b_unsigned`: B là gate unsigned; `rshift`: số bit chia lũy thừa 2 trước saturation; `product`: tích trung gian trước rescale; `result`: kết quả đã saturation; và 4 tín hiệu phụ khác trong đoạn code.

### [Dòng 16–43: Multiply/round/clamp](<../../../Verilog%20Source%20code/mul.sv#L16>)

**Mục đích.** Output result được làm tròn; output product không phải result đã đổi scale.

**Cách phần code hoạt động.** Có logic tổ hợp: output/intermediate được tính từ input hiện tại; các giá trị mặc định đầu khối giúp tránh suy ra latch.

**Tín hiệu và dữ liệu chính.** `b_s17`: B S17 sau chọn signed/gate; `b_unsigned`: B là gate unsigned; `b`: operand B; `p33`: tích đầy đủ S33 của helper mul; `a`: operand A; `product`: tích trung gian trước rescale; và 4 tín hiệu phụ khác trong đoạn code.
