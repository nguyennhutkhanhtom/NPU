# npu_pkg.sv — Kiểu dữ liệu, saturation và rounding

[Về mục lục](README.md) · [Về tổng quan](../README.md)

**Trạng thái:** Đang dùng — package chung.

**Source:** [npu_pkg.sv](<../../../Verilog%20Source%20code/npu_pkg.sv>). **Số dòng:** 117. **SHA-256:** `6c5c78b766028f558107b75a6aca8df65ade8c0d301d949f0fda1a49bc849fdb`.

## Khối này làm gì?

Package thống nhất format tensor, layout descriptor và các hàm số học. Đây là chỗ nên đọc trước các datapath. `logic signed` có sign bit nằm trong độ rộng đã ghi; S16 gồm cả bit dấu. `struct packed` ghép các trường thành một vector bit liên tục theo thứ tự khai báo.

## Sơ đồ kiến trúc tổng quan

```mermaid
flowchart TB
%%{init: {"flowchart": {"subGraphTitleMargin": {"top": 8, "bottom": 20}, "nodeSpacing": 28, "rankSpacing": 42, "curve": "linear"}}}%%
    subgraph PKG["npu_pkg — định nghĩa dùng khi elaboration, không phải instance phần cứng"]
        SIZE["Hằng số độ rộng / dung lượng<br/>SRAM 256 bit · K_MAX=512"]
        TYPE["Kiểu tensor + descriptor<br/>ws_desc_t 32 bit · mat_desc_t 96 bit"]
        ARITH["Hàm số học tổ hợp<br/>RNE / scale_shift / saturation"]
        CHECK["Hàm kiểm tra descriptor<br/>ws_words / ws_valid / ranges_overlap"]
    end
    TOP["Top + descriptor file + SRAM wrappers"]
    ENGINE["Row-wise / NORM / ternary engines"]
    SIZE -.->|"Kích thước RTL"| TOP
    SIZE -.-> ENGINE
    TYPE -.->|"Kiểu cổng và metadata"| TOP
    TYPE -.-> ENGINE
    ARITH -.->|"Logic triển khai tại nơi gọi"| ENGINE
    CHECK -.->|"Logic kiểm tra tại nơi gọi"| ENGINE
```

MUX dùng hình thang rộng ở phía nhiều ngõ vào và thu hẹp về ngõ ra; decoder/demux dùng hình thang ngược lại, mở rộng về phía nhiều ngõ ra. Hình chữ nhật có các vạch ngang biểu diễn bộ nhớ hoặc bank descriptor. Các hình chữ nhật thường là datapath, thanh ghi đơn hoặc giao diện. Nét liền là đường dữ liệu, nét đứt là điều khiển/cấu hình. Mũi tên hồi tiếp biểu diễn kết nối phần cứng. Sơ đồ không biểu diễn thứ tự chu kỳ, trạng thái FSM hoặc các tầng pipeline CPU. Đây là sơ đồ quan hệ định nghĩa RTL: package không tạo một instance phần cứng riêng. Các hàm tổ hợp được triển khai tại từng nơi gọi, không hàm ý một bộ số học dùng chung.

## Cách hoạt động chi tiết

`sat_s16/sat_s32` clamp về miền biểu diễn. `rne_shift64` tách sign và magnitude, xác định guard/sticky/LSB rồi làm tròn ties-to-even. `scale_shift64` dùng RNE khi chia cho 2^shift, hoặc shift trái khi phải tăng scale raw. Các hàm kiểm tra workspace tính số word bằng phép chia làm tròn lên.

1. Các parameter xác định biên thiết kế: word 256 bit, 32 ternary lane, hai vector lane và K tối đa 512. Một số module vẫn có literal theo cấu hình này, nên đổi package chưa đủ để tái cấu hình toàn chip.
2. Workspace descriptor mô tả địa chỉ, length, format và F_t. Matrix descriptor mô tả weight, bias, K, số hàng và postscale.
3. `rne_shift64` làm tròn trên magnitude rồi khôi phục dấu. Guard, sticky và LSB xử lý chính xác trường hợp nằm giữa hai số.
4. `sat_s16/sat_s32` clamp sau số học S64, tránh wrap-around khi lấy bit thấp.
5. `ws_words`, `ws_valid` và `ranges_overlap` là lớp kiểm tra memory được nhiều execution unit dùng chung.

## Các nhóm logic trong source

Source được chia theo chức năng. Mỗi nhóm giữ nguyên phạm vi dòng để đối chiếu, nhưng phần giải thích tập trung vào quan hệ giữa các câu lệnh thay vì lặp lại từng dấu ngoặc, khai báo hoặc phép gán.


### [Dòng 1–17: Thông số chung](<../../../Verilog%20Source%20code/npu_pkg.sv#L1>)

<!-- source-range:1:17 -->
```systemverilog
package npu_pkg;
    parameter int SRAM_W = 256;
    parameter int PARAM_AW = 10;
    parameter int WORK_AW = 8;
    parameter int PARAM_DEPTH = 1 << PARAM_AW; // 1024 words = 32 KiB
    parameter int WORK_DEPTH = 1 << WORK_AW; // 256 words = 8 KiB

    parameter int ACT_W = 8;
    parameter int STATE_W = 16;
    parameter int WEIGHT_W = 2;
    parameter int DOT_LANES = 32;
    parameter int VEC_LANES = 2;
    parameter int ACC_W = 18;
    parameter int K_MAX = 512;

    parameter int M_W = 24;
    parameter int SHIFT_W = 6;
```

**Mục đích.** SRAM 256 bit, 32 ternary lane, 2 vector lane, K tối đa 512. Thay hằng số riêng lẻ chưa đủ để tái cấu hình toàn RTL vì một số khối còn width cố định.

**Cách phần code hoạt động.** Nhóm này định nghĩa giao diện, độ rộng, kiểu hoặc tín hiệu trung gian. Nó tạo cấu trúc để các nhóm xử lý sau sử dụng, chưa tự biểu diễn một bước runtime riêng.


### [Dòng 18–46: Format và descriptor](<../../../Verilog%20Source%20code/npu_pkg.sv#L18>)

<!-- source-range:18:46 -->
```systemverilog

    typedef enum logic [1:0] {
    FMT_S8 = 2'h0,
    FMT_S16 = 2'h1,
    FMT_U16 = 2'h2,
    FMT_S32 = 2'h3
    } tensor_fmt_t;

    // Workspace descriptor. length counts logical elements, not SRAM words.
    typedef struct packed {
    logic [7:0] base_word;
    logic [9:0] length;
    tensor_fmt_t fmt;
    logic [4:0] frac_bits;
    logic [6:0] reserved;
    } ws_desc_t; // 32 bits

    // Ternary matrix descriptor. Each output row begins on a 256-bit word boundary.
    // Weight rows use ceil(K/128) words. Biases are S32, 8 values/word.
    typedef struct packed {
    logic [9:0] weight_base;
    logic [9:0] bias_base;
    logic [9:0] k_len;
    logic [9:0] n_rows;
    logic [23:0] scale_m;
    logic [5:0] scale_r;
    logic output_s32; // 0: saturate to S16, 1: saturate to S32
    logic [24:0] reserved; // bit0: dynamic q scale; bit1: no bias
    } mat_desc_t; // 96 bits
```

**Mục đích.** Length là số phần tử. Matrix row bắt đầu trên ranh giới word; bias S32 pack 8 phần tử/word.

**Cách phần code hoạt động.** Nhóm này định nghĩa giao diện, độ rộng, kiểu hoặc tín hiệu trung gian. Nó tạo cấu trúc để các nhóm xử lý sau sử dụng, chưa tự biểu diễn một bước runtime riêng.

**Tín hiệu và dữ liệu chính.** `base_word`: địa chỉ word 256 đầu tensor; `length`: số phần tử tensor; `frac_bits`: số bit phần lẻ của input; `reserved`: bit để dành hoặc flag mở rộng theo loại descriptor; `weight_base`: base word 256 của weight; `bias_base`: base word 256 của bias; và 5 tín hiệu phụ khác trong đoạn code.


### [Dòng 47–58: Saturation](<../../../Verilog%20Source%20code/npu_pkg.sv#L47>)

<!-- source-range:47:58 -->
```systemverilog

    function automatic logic signed [15:0] sat_s16(input logic signed [63:0] x);
        if (x > 64'sh0000_0000_0000_7fff) sat_s16 = 16'sh7fff;
        else if (x < - 64'sh0000_0000_0000_8000) sat_s16 = 16'sh8000;
        else sat_s16 = x[15:0];
    endfunction

    function automatic logic signed [31:0] sat_s32(input logic signed [63:0] x);
        if (x > 64'sh0000_0000_7fff_ffff) sat_s32 = 32'sh7fff_ffff;
        else if (x < - 64'sh0000_0000_8000_0000) sat_s32 = 32'sh8000_0000;
        else sat_s32 = x[31:0];
    endfunction
```

**Mục đích.** So sánh trong S64 trước khi lấy bit thấp, tránh wrap-around.

**Cách phần code hoạt động.** Có function tổ hợp dùng lại tại nơi gọi; function không giữ trạng thái qua các chu kỳ.

**Tín hiệu và dữ liệu chính.** `x`: giá trị đầu vào hàm số học.


### [Dòng 59–89: RNE](<../../../Verilog%20Source%20code/npu_pkg.sv#L59>)

<!-- source-range:59:89 -->
```systemverilog

    // Round-to-nearest-even signed arithmetic right shift.
    // shift=0 returns x unchanged. Intended for shift <= 47.
    function automatic logic signed [63:0] rne_shift64(
            input logic signed [63:0] x,
            input logic [5:0] shift
        );
        logic sign;
        logic [63:0] mag;
        logic [63:0] q;
        logic guard;
        logic sticky;
        logic lsb;
        logic inc;
        begin
            if (shift == 0) begin
                rne_shift64 = x;
            end else begin
                sign = x[63];
                mag = sign ? $unsigned( - x) : $unsigned(x);
                q = mag >> shift;
                guard = mag[shift - 1];
                sticky = (shift > 1) ? | (mag & ((64'h1 << (shift - 1)) - 1)) : 1'b0;
                lsb = q[0];
                inc = guard & (sticky | lsb);
                q = q + inc;
                rne_shift64 = sign ? - $signed(q) : $signed(q);
            end
        end
    endfunction

```

**Mục đích.** Guard là bit ngay dưới phần giữ lại. Sticky OR các bit thấp hơn; khi đúng nửa đơn vị, chỉ tăng nếu LSB đang lẻ.

**Cách phần code hoạt động.** Có function tổ hợp dùng lại tại nơi gọi; function không giữ trạng thái qua các chu kỳ.

**Tín hiệu và dữ liệu chính.** `x`: giá trị đầu vào hàm số học; `shift`: độ dịch để biểu diễn scale; ý nghĩa dấu theo hàm đang dùng; `sign`: bit dấu của input; `mag`: magnitude unsigned của input; `q`: magnitude sau shift; `guard`: bit ngay dưới phần giữ lại; và 3 tín hiệu phụ khác trong đoạn code.

**Điểm cần đọc kỹ.** Điểm khó của nhóm này là RNE cho số âm. Code không dịch trực tiếp số âm rồi cộng guard; nó làm tròn magnitude unsigned trước, sau đó mới khôi phục dấu để kết quả đối xứng quanh zero.

#### Sơ đồ khối phần cứng của nhóm

```mermaid
flowchart TB
%%{init: {"flowchart": {"subGraphTitleMargin": {"top": 8, "bottom": 20}, "nodeSpacing": 28, "rankSpacing": 42, "curve": "linear"}}}%%
    X["x signed S64"] --> MAG["Sign / magnitude combinational logic"]
    R["shift U6"] -.-> SH["Unsigned right shifter"]
    MAG --> SH
    MAG --> BITS["Guard / sticky bit extraction"]
    R -.-> BITS
    SH --> INC["Magnitude incrementer"]
    SH -->|"Quotient LSB"| ROUND["RNE decision logic<br/>guard AND sticky-or-LSB"]
    BITS --> ROUND
    ROUND -.-> INC
    INC --> SIGN@{ shape: trap-t, label: "Sign restoration + shift-zero bypass selector" }
    MAG -.->|"Sign"| SIGN
    X -->|"Unshifted bypass"| SIGN
    R -.-> SIGN
    SIGN --> OUT["Rounded signed S64<br/>Combinational logic at each caller"]
```


### [Dòng 90–98: Đổi scale](<../../../Verilog%20Source%20code/npu_pkg.sv#L90>)

<!-- source-range:90:98 -->
```systemverilog
    // Shift is positive for division, negative for multiplication by a power of two.
    // Callers constrain left shifts to <=24 and operands to at most 33 signed bits.
    function automatic logic signed [63:0] scale_shift64(
            input logic signed [63:0] x, input integer shift
        );
        if (shift >= 0) scale_shift64 = rne_shift64(x, shift[5:0]);
        else scale_shift64 = x <<< ( - shift);
    endfunction

```

**Mục đích.** Shift dương chia và RNE; shift âm nhân lũy thừa hai. Caller phải bảo đảm miền shift và operand không tràn.

**Cách phần code hoạt động.** Có function tổ hợp dùng lại tại nơi gọi; function không giữ trạng thái qua các chu kỳ.

**Tín hiệu và dữ liệu chính.** `x`: giá trị đầu vào hàm số học; `shift`: độ dịch để biểu diễn scale; ý nghĩa dấu theo hàm đang dùng.


### [Dòng 99–117: Kiểm tra memory](<../../../Verilog%20Source%20code/npu_pkg.sv#L99>)

<!-- source-range:99:117 -->
```systemverilog
    function automatic integer ws_words(input ws_desc_t d);
        case (d.fmt)
            FMT_S8 : ws_words = (int'(d.length) + 31) / 32;
            FMT_S16, FMT_U16 : ws_words = (int'(d.length) + 15) / 16;
            default : ws_words = (int'(d.length) + 7) / 8;
        endcase
    endfunction

    function automatic logic ws_valid(input ws_desc_t d);
        ws_valid = d.length > 0 && d.length <= K_MAX && d.frac_bits <= 24 &&
        int'(d.base_word) + ws_words(d) <= WORK_DEPTH;
    endfunction

    function automatic logic ranges_overlap(input integer a, input integer an,
            input integer b, input integer bn);
        ranges_overlap = a < b + bn && b < a + an;
    endfunction

endpackage
```

**Mục đích.** Tính ceil(length/elements_per_word), kiểm tra cuối vùng SRAM và phép giao nhau của hai khoảng nửa mở [base, base+size).

**Cách phần code hoạt động.** Có function tổ hợp dùng lại tại nơi gọi; function không giữ trạng thái qua các chu kỳ.

**Tín hiệu và dữ liệu chính.** `length`: số phần tử tensor; `frac_bits`: số bit phần lẻ của input; `base_word`: địa chỉ word 256 đầu tensor; `a`: operand A; `b`: operand B.

