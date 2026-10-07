# mul.sv — Helper nhân S16 và gate

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Helper — không instantiate trong top hiện tại.

**Source:** [mul.sv](<../../../Verilog%20Source%20code/mul.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Helper nhân a signed 16 với b signed 16 hoặc unsigned gate. Rowwise_op đã có đường nhân chia sẻ MUL/REC riêng; không cộng helper này vào số multiplier của top. |

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
A["a S16"] --> MUL["Signed multiplier<br/>S16 × S17 → S33"]
    B["b 16 bit"] --> EXT@{ shape: trap-t, label: "Sign/zero-extension selector" }
    U["b_unsigned"] -.-> EXT
    EXT --> MUL
    MUL --> P["product output<br/>Low 32 bits"]
    MUL --> RNE["Sign-extend S64 + RNE shifter"]
    SHIFT["rshift"] -.-> RNE
    RNE --> SAT["S16 saturator + range checker"]
    B --> GATE["Gate range detector<br/>Raw value above 0x8000"]
    U -.-> GATE
    SAT --> R["result S16"]
    SAT -.-> OV["Overflow OR logic"]
    GATE -.-> OV
    OV --> O["overflow"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
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
