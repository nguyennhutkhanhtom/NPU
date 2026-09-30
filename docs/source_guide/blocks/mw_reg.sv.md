# mw_reg.sv — Pipeline register Memory → Write Back

[Về mục lục](README.md) · [Về tổng quan](../README.md)

**Trạng thái:** Legacy — không nối vào matmulfree hiện tại.

**Source:** [mw_reg.sv](<../../../Verilog%20Source%20code/mw_reg.sv>). **Số dòng:** 10. **SHA-256:** `8f27a55bda16912be3fb069bd6cf09abaf740a186c9b2503171158bb59109960`.

## Khối này làm gì?

File giữ memory/ALU result256 bit, instruction và write-back control giữa stage Memory và Write Back của cấu trúc pipeline cũ. Bản đang nằm trong source đã đổi payload liên quan sang256 bit, nên cũng không phải nguyên văn source thesis. Scheduler v2 không instantiate file này.

## Sơ đồ kiến trúc tổng quan

```mermaid
flowchart LR
%%{init: {"flowchart": {"subGraphTitleMargin": {"top": 8, "bottom": 20}, "nodeSpacing": 28, "rankSpacing": 42, "curve": "linear"}}}%%
    IN["Input payload<br/>Instruction + PC + hai result 256 bit + control"] --> BANK["Bank thanh ghi legacy độc lập<br/>Load enable + reset/flush clear"]
    EN["enable"] -.-> BANK
    RESET["clk / rst_n / flush"] -.-> BANK
    BANK --> OUT["Output payload cùng cấu trúc"]
```

MUX dùng hình thang rộng ở phía nhiều ngõ vào và thu hẹp về ngõ ra; decoder/demux dùng hình thang ngược lại, mở rộng về phía nhiều ngõ ra. Hình chữ nhật có các vạch ngang biểu diễn bộ nhớ hoặc bank descriptor. Các hình chữ nhật thường là datapath, thanh ghi đơn hoặc giao diện. Nét liền là đường dữ liệu, nét đứt là điều khiển/cấu hình. Mũi tên hồi tiếp biểu diễn kết nối phần cứng. Sơ đồ không biểu diễn thứ tự chu kỳ, trạng thái FSM hoặc các tầng pipeline CPU. Sơ đồ riêng của module legacy/helper; module này không được instantiate trong hierarchy matmulfree hiện tại.

## Cách hoạt động chi tiết

Ở posedge clk, enable=1 cho phép chép toàn bộ input sang output. Nếu reset hoặc flush, output về 0; reset active-low asynchronous, flush synchronous và ưu tiên hơn enable. Khi enable=0, thanh ghi giữ nguyên. Các assignment nằm cùng dòng vẫn là cập nhật song song tại một cạnh clock.

1. Module giữ memory output, ALU output và control từ Memory sang Write Back.
2. Reset/flush xóa write enable và payload để instruction bị flush không ghi kết quả.
3. Enable chốt mọi trường đồng thời; mux chọn nguồn write-back nằm ngoài module.
4. Đây là pipeline register legacy, không quyết định hành vi core hiện tại.

## Các nhóm logic trong source

Source được chia theo chức năng. Mỗi nhóm giữ nguyên phạm vi dòng để đối chiếu, nhưng phần giải thích tập trung vào quan hệ giữa các câu lệnh thay vì lặp lại từng dấu ngoặc, khai báo hoặc phép gán.


### [Dòng 1–10: Giao diện và register](<../../../Verilog%20Source%20code/mw_reg.sv#L1>)

<!-- source-range:1:10 -->
```systemverilog
module mw_reg(
    input logic clk, rst_n, enable, flush, input logic [12:0] instr_mw,
    input logic [255:0] mem_out_mw_0, alu_out_mw, input logic wb_sel_mw, reg_wr_en_mw, input logic [8:0] pc_mw,
    output logic [12:0] instr_wb, output logic [255:0] mem_out_wb_0, alu_out_wb, output logic reg_wr_en_wb, wb_sel_wb, output logic [8:0] pc_wb
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin instr_wb <= 0;mem_out_wb_0 <= 0;alu_out_wb <= 0;reg_wr_en_wb <= 0;wb_sel_wb <= 0;pc_wb <= 0;end
        else if (enable) begin instr_wb <= instr_mw;mem_out_wb_0 <= mem_out_mw_0;alu_out_wb <= alu_out_mw;reg_wr_en_wb <= reg_wr_en_mw;wb_sel_wb <= wb_sel_mw;pc_wb <= pc_mw;end
    end
endmodule
```

**Mục đích.** Các suffix của tín hiệu là tên giữ lại từ pipeline cũ. Sự có mặt của file không chứng minh top hiện tại có stage tương ứng.

**Cách phần code hoạt động.** Có logic tuần tự: register/FSM chỉ cập nhật tại cạnh clock; nonblocking assignment đọc giá trị cũ ở vế phải rồi chốt đồng thời.

**Tín hiệu và dữ liệu chính.** `enable`: cho phép pipeline register nhận input; `flush`: xóa payload/control của pipeline register.

