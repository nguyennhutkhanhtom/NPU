# Cấu hình scaled-down

Đã tạo `scaled_profiles.sv` với hai package riêng. RTL trong `Verilog Source code` không bị thay đổi. Cấu hình nhỏ không thể khắc phục các functional bug của bản gốc.

## A. Cấu hình chạy được ngay ở cấp module

`scaled_leaf_profile` dùng cho register/mem_mapping/mem_burst. Đây là cấu hình structural/handshake, không phải phiên bản số học 4-bit của toàn bộ coprocessor.

| Thông số | Mặc định | Scaled A | Giới hạn |
|---|---:|---:|---|
| register DATA_WIDTH | 16 | 4 | Chỉ kiểm bit transport, không gọi ALU16-bit |
| register ADDR_WIDTH | 3 | 2 | Chọn R0..R3 |
| register MEM_DEPTH | 1024 | 64 | 4 vector x16 word; không được đặt depth4 |
| register word width | 512 | 128 | Vẫn32 lane |
| mem_mapping DATA_WIDTH | 16 | 4 | Không nối vào ternary_mul512-bit |
| mem_mapping MEM_DEPTH | 524288 | 8192 | Phủ matrix selector7:7168..8191 |
| mem_mapping selector width | 3 | 3 | Không parameter trong RTL hiện tại |
| Internal RAM pointer width | 19 | 19 | Vẫn hard-code; không giả vờ đã giảm pointer |
| mem_burst MEM_DATA_BITS | 512 | 32 | Chỉ interface model, không MIG board thật |
| mem_burst ADDR_BITS | 28 | 6 | Request start0..7; start+len<=8 tránh wrap do shift3 |
| mem_burst length width | 10 | 10 | Không parameter; dùng1..8 trong profile này |

Instantiation tương ứng:

```systemverilog
import scaled_leaf_profile::*;
register #(.DATA_WIDTH(DATA_W), .ADDR_WIDTH(REG_ADDR_W), .MEM_DEPTH(REG_DEPTH)) rf (...);
mem_mapping #(.DATA_WIDTH(DATA_W), .MEM_DEPTH(MEM_DEPTH)) ram (...);
mem_burst #(.MEM_DATA_BITS(BURST_DATA_W), .ADDR_BITS(BURST_ADDR_W)) ddr_model (...);
```

`tb_scaled_leaf.sv` instantiate đúng package này để kiểm transport/boundary. Bộ `../sim/tb_review.sv` có cùng giá trị cấu hình trong `scaled_config.svh`, đã tái hiện17 điều kiện baseline. Các RAM/LUT zero chỉ phục vụ structural tests.

## B. Cấu hình toàn hệ thống cho patch parameterization

`scaled_system_profile` là cấu hình cụ thể đã compile và kiểm consistency; **chưa phải runnable matmulfree**, vì top không có parameter và ALU8-bit đang fail elaboration. Tách trạng thái này để tránh tạo một wrapper có bus truncate nhưng âm thầm thay đổi behavior.

| Thông số | Thiết kế gốc | Target B |
|---|---:|---:|
| Pipeline/ISA | 5 stage /13-bit | Giữ nguyên |
| Số register/selector | 8 /3-bit | Giữ nguyên |
| Lane count | 32 | 32 |
| Vector /matrix | 512 /512x512 | Giữ nguyên |
| Data /fraction bits | 16 /12 (comment MUL) | 8 /4 |
| Khoảng signed fixed-point | [-8,8) | [-8,8) |
| Độ phân giải | 1/4096 | 1/16 |
| Word width | 512 | 256 |
| Vector words | 16 | 16 |
| Ternary weights/word | 256 | 128 |
| Matrix words/stride | 1024 | **2048** |
| Register depth | 1024 allocated,128 addressable | 128 |
| Register pointer | 19 | 7 |
| Main RAM depth | 524288 | 16384 |
| Main RAM pointer | 19 | 14 |
| Instruction ROM depth/PC | 512 /9-bit | 64 /6-bit |
| Activation buffer pointer | 4 | 4 |
| Ternary buffer pointer | 10 | 11 |
| Accumulator safe width | RTL16; conservative26 cần cho miền đầy đủ | 18 (8+1+9) |

Giảm data width làm số word chứa cùng ma trận ternary **tăng gấp đôi**. Không được giữ literal1024 hoặc pointer10-bit. Profile vẫn giảm main RAM từ32MiB logical xuống512KiB, register RAM từ64KiB xuống4KiB. Đây là dung lượng khai báo logic, không phải dự đoán BRAM sau synthesis.

Quan hệ bắt buộc:

```text
WORD_W = DATA_W * LANES
VECTOR_WORDS = ceil(VECTOR_ELEMS / LANES)
TERNARY_PER_WORD = WORD_W / 2
MATRIX_WORDS = ceil(MATRIX_ROWS * VECTOR_ELEMS / TERNARY_PER_WORD)
REG_DEPTH >= REG_COUNT * VECTOR_WORDS
MEM_DEPTH >= REG_COUNT * MATRIX_STRIDE
PTR_W = max(1, ceil(log2(DEPTH)))
TERM_W = DATA_W + 1  // sign extension BEFORE ternary negation
ACC_W = TERM_W + ceil(log2(VECTOR_ELEMS))
```

Tất cả threshold/end/count derive từ số beat và latency thực, không giữ `12/15/1020/1023`. Vector/bank/matrix offsets phải cùng một quy ước ở encoder, init data, mapper và test oracle. Constant ACTIVATION_BASE trong package B là quan hệ cơ học với matrix stride hiện có, **chưa giải quyết lỗi routing/map F25**. Không đặt operand đang sống vào các vùng alias/overlap ngoài hợp đồng layout; cần kiểm STV -> TMATMUL sử dụng đúng dữ liệu vừa ghi.

Các ràng buộc bảo toàn behavior:

- Giữ opcode, hướng dữ liệu, số register/lane, kích thước vector và kiến trúc pipeline. Không thêm pipeline register vào adder tree chỉ để scale.
- Data8-bit giữ phép toán nhưng giảm precision. Không thể giữ bit-exact16-bit với mọi input. Reference model dùng cùng quantization, hoặc dùng miền giao nhau representable khi so sánh hai profile.
- PC6-bit chỉ hỗ trợ program tối đa64 instruction và phải HALT trước khi wrap. Không tuyên bố tương đương cho program dài hơn.
- Không giảm fixed-point bus bằng nối zero-extend: raw8'hf0 là -1 Q4.4, không phải +240 hoặc giá trị Q4.12. Cần signed casts và rescale explicit.
- Giữ2-bit ternary. Bổ sung assertion encoding00/01/11, nếu10 reserved.
- mem_burst hiện là module độc lập; không tích hợp DDR mới vào core trong patch scale. Profile bus nhỏ chỉ dùng simulator; MIG implementation cần phù hợp cấu hình IP thật.
- Nếu sau này vận chuyển matrix2048 word bằng burst10-bit, tách request tối đa1023 beat hoặc thay hợp đồng length. Không gán2048 vào10 bit.
- Thay width phải đi kèm sinh lại LUT/program/data đúng format. Chưa có dữ liệu gốc để chứng minh accuracy toàn chương trình.

## Chạy lại

Trong PowerShell tại workspace:

```powershell
./review/sim/run.ps1
./review/audit_20260916/run_extended.ps1
./review/audit_20260916/run_profiles.ps1
```

`run_profiles.ps1` kiểm consistency profile B, chạy leaf profile A, rồi **mong đợi** probe ALU8-bit báo lỗi width. Sau patch tương lai phải đổi expected failure này thành functional pass và giữ regression16-bit.
