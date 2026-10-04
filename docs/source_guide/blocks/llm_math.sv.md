# llm_math.sv — SIMD byte-product pipeline và reduction

[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)

**Source:** [llm_math.sv](<../../../Verilog%20Source%20code/llm_math.sv>). **Số dòng:** 70. **SHA-256:** `259a6b2576ce705eaf4df390497fcc406d0f8a5c7887c0d891b5423a8da8b187`.

## Khối này làm gì?

32 tích S24×S32 tạo S56 bằng partial products byte: ba byte thấp U8, byte cao S8. Partial S33, cặp S41, ghép product S56 rồi cây cộng cân bằng tới S61. Done chín cạnh sau cạnh nhận start. Chỉ dùng logic cells; input chốt khi start và không busy. Payload không reset; pipeline valid reset hủy transaction.

## Sơ đồ kiến trúc

```mermaid
flowchart TB
    IN[32 pairs S24 and S32] --> CAP[Input registers]
    CAP --> MUL[Four byte products per lane S33]
    MUL --> PAIR[Registered pair sums S41]
    PAIR --> PRODUCT[Registered product S56]
    PRODUCT --> TREE[Five registered reduction levels]
    TREE --> SUM[Sum S61]
    CTRL[10-bit validity pipeline] -.-> CAP
    CTRL -.-> TREE
    CTRL --> DONE[busy and done after nine clocks]
```

## Cách hoạt động chi tiết

32 tích S24×S32 tạo S56 bằng partial products byte: ba byte thấp U8, byte cao S8. Partial S33, cặp S41, ghép product S56 rồi cây cộng cân bằng tới S61. Done chín cạnh sau cạnh nhận start. Chỉ dùng logic cells; input chốt khi start và không busy. Payload không reset; pipeline valid reset hủy transaction.

## Các nhóm logic trong source

### [Dòng 1–11: Interface and payload](<../../../Verilog%20Source%20code/llm_math.sv#L1>)

<!-- source-range:1:11 -->
```systemverilog
// Shared fixed-point SIMD arithmetic for autonomous language inference.
// Payload registers are valid only while the control pipeline is active.
module llm_math (
    input logic clk, rst_n, start,
    input logic signed [23:0] a [0:31],
    input logic signed [31:0] b [0:31],
    output logic busy, done,
    output logic signed [55:0] product [0:31],
    output logic signed [60:0] sum
);
    // Bit-product compressor trees and pair sums split arithmetic across edges.
```

Dải product và sum đủ cho signed extremes; payload chỉ hợp lệ sau transaction đã hoàn thành.

### [Dòng 12–26: Widths and control pipeline](<../../../Verilog%20Source%20code/llm_math.sv#L12>)

<!-- source-range:12:26 -->
```systemverilog
    logic [9:0] valid_q;
    logic signed [23:0] a_q [0:31];
    logic signed [31:0] b_q [0:31];
    logic signed [32:0] partial_q [0:31][0:3];
    wire [32:0] partial_comb [0:31][0:3];
    genvar mul_lane, mul_part;
    generate
    for (mul_lane = 0; mul_lane < 32; mul_lane = mul_lane + 1) begin : g_mul_lane
        for (mul_part = 0; mul_part < 4; mul_part = mul_part + 1) begin : g_byte
            logic_mul #(.A_W(24), .B_W(8), .OUT_W(33), .SIGNED_A(1), .SIGNED_B(mul_part == 3)) u_mul
                (.a(a_q[mul_lane]), .b(b_q[mul_lane][(mul_part << 3) +: 8]), .product(partial_comb[mul_lane][mul_part]));
        end
    end
    endgenerate
    logic signed [40:0] pair_q [0:31][0:1];
```

busy là OR valid; request trong busy bị bỏ qua. done tại valid_q[9], chín cạnh sau cạnh nhận start. Signed casts giữ sign extension.

### [Dòng 27–38: Operand capture and byte multiplication](<../../../Verilog%20Source%20code/llm_math.sv#L27>)

<!-- source-range:27:38 -->
```systemverilog
    logic signed [56:0] level1 [0:15];
    logic signed [57:0] level2 [0:7];
    logic signed [58:0] level3 [0:3];
    logic signed [59:0] level4 [0:1];
    assign busy = |valid_q;
    assign done = valid_q[9];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_q <= 0;
        else valid_q <= {valid_q[8:0], start && !busy};
    end
    always_ff @(posedge clk) begin
        if (rst_n && start && !busy)
```

Các byte thấp có leadingzero trước signed cast; byte cao giữ dấu. Partial products giữ đủ S33 trước shift.

### [Dòng 39–47: Pair and product reconstruction](<../../../Verilog%20Source%20code/llm_math.sv#L39>)

<!-- source-range:39:47 -->
```systemverilog
            for (int i = 0; i < 32; i = i + 1) begin
                a_q[i] <= a[i];
                b_q[i] <= b[i];
            end
        if (valid_q[0])
            for (int i = 0; i < 32; i = i + 1) begin
                for (int part = 0; part < 4; part = part + 1)
                    partial_q[i][part] <= partial_comb[i][part];
            end
```

Hai pair dùng shift8/S41; product ghép shift16/S56. Không truncate intermediate trước khi dấu và độ rộng đã đúng.

### [Dòng 48–70: Balanced reduction](<../../../Verilog%20Source%20code/llm_math.sv#L48>)

<!-- source-range:48:70 -->
```systemverilog
        if (valid_q[1])
            for (int i = 0; i < 32; i = i + 1) begin
                pair_q[i][0] <= 41'(partial_q[i][0]) + (41'(partial_q[i][1]) <<< 8);
                pair_q[i][1] <= 41'(partial_q[i][2]) + (41'(partial_q[i][3]) <<< 8);
            end
        if (valid_q[2])
            for (int i = 0; i < 32; i = i + 1)
                product[i] <= 56'(pair_q[i][0]) + (56'(pair_q[i][1]) <<< 16);
        if (valid_q[3])
            for (int i = 0; i < 16; i = i + 1)
                level1[i] <= 57'(product[2 * i]) + 57'(product[2 * i + 1]);
        if (valid_q[4])
            for (int i = 0; i < 8; i = i + 1)
                level2[i] <= 58'(level1[2 * i]) + 58'(level1[2 * i + 1]);
        if (valid_q[5])
            for (int i = 0; i < 4; i = i + 1)
                level3[i] <= 59'(level2[2 * i]) + 59'(level2[2 * i + 1]);
        if (valid_q[6])
            for (int i = 0; i < 2; i = i + 1)
                level4[i] <= 60'(level3[2 * i]) + 60'(level3[2 * i + 1]);
        if (valid_q[7]) sum <= 61'(level4[0]) + 61'(level4[1]);
    end
endmodule
```

Mỗi level tăng một bit; S61 chứa tổng32tích. Numeric expectations S128 giữ nguyên, chỉ latency/reset coverage đổi7→9.
