# fd_reg.sv — Pipeline register Fetch → Decode

[Tài liệu](../../README.md) → [Hierarchy RTL](../README.md) → [Mục lục từng file](README.md)

**Trạng thái:** Legacy — không nối vào matmulfree hiện tại.

**Source:** [fd_reg.sv](<../../../Verilog%20Source%20code/fd_reg.sv>). **Số dòng:** 12. **SHA-256:** `75de20e3fb5abe35246fc7f003a6159ce7f78a38b80e6a26d795881b56811565`.

## Khối này làm gì?

File giữ instruction13 bit và PC9 bit giữa stage Fetch và Decode của cấu trúc pipeline cũ. Bản đang nằm trong source đã đổi payload liên quan sang256 bit, nên cũng không phải nguyên văn source thesis. Scheduler v2 không instantiate file này.

## Sơ đồ kiến trúc tổng quan

```mermaid
flowchart LR
%%{init: {"flowchart": {"subGraphTitleMargin": {"top": 8, "bottom": 20}, "nodeSpacing": 28, "rankSpacing": 42, "curve": "linear"}}}%%
    IN["Input payload<br/>Instruction 13 bit + PC 9 bit"] --> BANK["Bank thanh ghi legacy độc lập<br/>Load enable + reset/flush clear"]
    EN["enable"] -.-> BANK
    RESET["clk / rst_n / flush"] -.-> BANK
    BANK --> OUT["Output payload cùng cấu trúc"]
```

MUX dùng hình thang rộng ở phía nhiều ngõ vào và thu hẹp về ngõ ra; decoder/demux dùng hình thang ngược lại, mở rộng về phía nhiều ngõ ra. Hình chữ nhật có các vạch ngang biểu diễn bộ nhớ hoặc bank descriptor. Các hình chữ nhật thường là datapath, thanh ghi đơn hoặc giao diện. Nét liền là đường dữ liệu, nét đứt là điều khiển/cấu hình. Mũi tên hồi tiếp biểu diễn kết nối phần cứng. Sơ đồ không biểu diễn thứ tự chu kỳ, trạng thái FSM hoặc các tầng pipeline CPU. Sơ đồ riêng của module legacy/helper; module này không được instantiate trong hierarchy matmulfree hiện tại.

## Cách hoạt động chi tiết

Ở posedge clk, enable=1 cho phép chép toàn bộ input sang output. Nếu reset hoặc flush, output về 0; reset active-low asynchronous, flush synchronous và ưu tiên hơn enable. Khi enable=0, thanh ghi giữ nguyên. Các assignment nằm cùng dòng vẫn là cập nhật song song tại một cạnh clock.

1. Reset hoặc flush xóa instruction và PC ở phía Decode.
2. Enable bằng 1 chốt instruction/PC từ Fetch sang output tại cùng cạnh clock.
3. Enable bằng 0 giữ output, tạo stall giữa Fetch và Decode.
4. Module thuộc pipeline legacy; scheduler v2 không instantiate nó.

## Các nhóm logic trong source

Source được chia theo chức năng. Mỗi nhóm giữ nguyên phạm vi dòng để đối chiếu, nhưng phần giải thích tập trung vào quan hệ giữa các câu lệnh thay vì lặp lại từng dấu ngoặc, khai báo hoặc phép gán.


### [Dòng 1–12: Giao diện và register](<../../../Verilog%20Source%20code/fd_reg.sv#L1>)

<!-- source-range:1:12 -->
```systemverilog
module fd_reg(
    input logic clk, rst_n, enable, flush,
    input logic [12:0] instr_fd,
    input logic [8:0] pc,
    output logic [12:0] instr_de,
    output logic [8:0] pc_de
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin instr_de <= 0;pc_de <= 0;end
        else if (enable) begin instr_de <= instr_fd;pc_de <= pc;end
    end
endmodule
```

**Mục đích.** Các suffix của tín hiệu là tên giữ lại từ pipeline cũ. Sự có mặt của file không chứng minh top hiện tại có stage tương ứng.

**Cách phần code hoạt động.** Có logic tuần tự: register/FSM chỉ cập nhật tại cạnh clock; nonblocking assignment đọc giá trị cũ ở vế phải rồi chốt đồng thời.

**Tín hiệu và dữ liệu chính.** `enable`: cho phép pipeline register nhận input; `flush`: xóa payload/control của pipeline register; `pc`: địa chỉ instruction hiện tại.
