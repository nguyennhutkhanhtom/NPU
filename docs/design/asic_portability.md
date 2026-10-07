# Khả năng chuyển sang ASIC và các implementation cell được phép

> **Category: POLICY.**

[Tài liệu](../README.md) · [Toàn RTL graph](full_rtl_language.md) · [Source số học](../source_guide/blocks/logic_mul.sv.md) · [Memory boundary](../source_guide/blocks/quartus_word_ram.sv.md)

[Hướng dẫn liên kết SRAM cho ASIC](asic_memory_binding.md) ghi lại contract
leaf/client, toàn bộ các mảng nhỏ được infer và evidence full-top elaboration
không phụ thuộc vendor memory.

RTL compute và control hiện tại dùng register, mux, phép so sánh, logic bitwise,
phép shift, phép cộng/trừ, counter và FSM. RTL không instantiate vendor arithmetic,
DSP, MAC, divider, square-root, FIFO, PLL, shift-register, floating-point hoặc
Qsys/Platform Designer IP. Multiplier dùng `logic_mul`; datapath không có toán tử
nhân hoặc chia số học tại runtime. Các biểu thức về generate geometry và constant
bit-slice offset là phép toán tại elaboration, không phải multiplier hoặc divider
phần cứng. Phép tính address/word-count lũy thừa hai tại runtime dùng shift trực
tiếp; các address factor hằng số nhỏ dùng shift/add.

[Quy tắc RTL](rtl_style.md) cấm synthesizable task, ownership tuần tự bị che khuất
và loop biến thiên/không giới hạn. Cả 61 request helper trước đây đều là inline
FSM update. Các phần replication lớn và pipeline stage dùng generate block; LUT
là combinational module tường minh. SIMD payload stage chạy từ operand đã capture,
với response contract chín clock. Hai FF tiêu chuẩn assert internal reset ngay lập
tức và release sau hai rising edge. Xem [chính sách RTL](rtl_style.md).

`logic_mul` chọn signedness độc lập cho A và B. A được mở rộng đến output width,
sau đó mỗi bit của B mask một row đã shift theo hằng số. Signed top bit đóng góp
negative shifted row thông qua phép bù cộng một. Mỗi compressor thay ba row bằng
XOR sum và shifted majority carry. Một adder thông thường kết hợp hai row cuối.
Kết quả theo modulo `2^OUT_W`; caller sở hữu logic rounding, saturation và overflow.
Register cùng pipeline valid/reset vẫn nằm trong caller, bảo toàn operation latency
hiện tại. Divider dùng shift/subtract với borrow flag; integer square root xử lý
radicand theo từng hai bit và dùng trial subtraction. Không có compute branch dành
riêng cho synthesis chọn thuật toán khác.

Vendor primitive trực tiếp duy nhất là `altsyncram`, được giới hạn trong
`quartus_word_ram`. Client truy cập primitive này qua `pipelined_word_ram` và
các bank/parameter adapter. Khi tích hợp ASIC, thay memory technology leaf bằng
foundry SRAM đã chọn và giữ đúng contract: common-clock 1R/1W, một raw read edge,
OLD_DATA khi read/write đồng thời trên cùng địa chỉ và không reset storage. Nếu
macro có collision rule hoặc latency khác, hãy điều chỉnh bên trong boundary này
và xác minh lại các test collision/reset/cancellation hiện có. Compute interface
và thuật toán số học không đổi. Physical constraint, library, SRAM view và kiểm tra
signoff ASIC vẫn là công việc theo technology; Quartus fitting chỉ minh họa
synthesis/timing.

Hint `dont_merge` cục bộ trong memory chỉ ảnh hưởng đến placement register trên
FPGA. ASIC tool có thể bỏ qua hoặc loại bỏ các hint này tại memory binding;
compute/control không dùng chúng. QSF vô hiệu hóa DSP và automatic shift-register
recognition. I/O standard, pin location và packed output-register request trong
QSF là FPGA physical binding, không phải RTL portable hoặc arithmetic IP.

Quartus là EDA demonstration backend. Các assignment về device, pin, I/O standard,
fanout và physical delay nằm trong QSF; chúng không trở thành dependency của
datapath/control ASIC. Demo SDC vẫn giữ 10 ns với input/output budget ban đầu,
không có false path hoặc multicycle path. Công việc này không bao gồm routing,
termination và peripheral bring-up trên board FPGA. Synthesis/STA ASIC thực tế
dùng standard-cell library, SRAM view và physical constraint đã chọn.

Trạng thái verification và implementation hiện tại: [optimization status](../verification/optimization_status.md).
