# de_reg.sv — Pipeline register Decode → Execute

[Tài liệu](../../README.md) → [Hierarchy RTL](../README.md) → [Mục lục từng file](README.md)

**Trạng thái:** Legacy — không nối vào matmulfree hiện tại.

**Source:** [de_reg.sv](<../../../Verilog%20Source%20code/de_reg.sv>). **Số dòng:** 16. **SHA-256:** `dbb7c23f6bda7e1f5b435bd34fbb4cdca9ef63f6af3a9b535cf4030f7f3dd50d`.

## Khối này làm gì?

File giữ instruction, hai operand256 bit và control giữa stage Decode và Execute của cấu trúc pipeline cũ. Bản đang nằm trong source đã đổi payload liên quan sang256 bit, nên cũng không phải nguyên văn source thesis. Scheduler v2 không instantiate file này.

## Sơ đồ kiến trúc tổng quan

```mermaid
flowchart LR
%%{init: {"flowchart": {"subGraphTitleMargin": {"top": 8, "bottom": 20}, "nodeSpacing": 28, "rankSpacing": 42, "curve": "linear"}}}%%
    IN["Input payload<br/>Instruction + PC + hai operand 256 bit + control"] --> BANK["Bank thanh ghi legacy độc lập<br/>Load enable + reset/flush clear"]
    EN["enable"] -.-> BANK
    RESET["clk / rst_n / flush"] -.-> BANK
    BANK --> OUT["Output payload cùng cấu trúc"]
```

MUX dùng hình thang rộng ở phía nhiều ngõ vào và thu hẹp về ngõ ra; decoder/demux dùng hình thang ngược lại, mở rộng về phía nhiều ngõ ra. Hình chữ nhật có các vạch ngang biểu diễn bộ nhớ hoặc bank descriptor. Các hình chữ nhật thường là datapath, thanh ghi đơn hoặc giao diện. Nét liền là đường dữ liệu, nét đứt là điều khiển/cấu hình. Mũi tên hồi tiếp biểu diễn kết nối phần cứng. Sơ đồ không biểu diễn thứ tự chu kỳ, trạng thái FSM hoặc các tầng pipeline CPU. Sơ đồ riêng của module legacy/helper; module này không được instantiate trong hierarchy matmulfree hiện tại.

## Cách hoạt động chi tiết

Ở posedge clk, enable=1 cho phép chép toàn bộ input sang output. Nếu reset hoặc flush, output về 0; reset active-low asynchronous, flush synchronous và ưu tiên hơn enable. Khi enable=0, thanh ghi giữ nguyên. Các assignment nằm cùng dòng vẫn là cập nhật song song tại một cạnh clock.

1. Module giữ instruction, hai operand 256 bit, PC và control từ Decode sang Execute.
2. Reset/flush xóa data và enable control để instruction bị loại không tạo side effect.
3. Enable chốt toàn bộ payload đồng thời; enable bằng 0 giữ dữ liệu cũ.
4. Các assignment cùng dòng vẫn cập nhật đồng thời. Module không nằm trong hierarchy v2.

## Các nhóm logic trong source

Source được chia theo chức năng. Mỗi nhóm giữ nguyên phạm vi dòng để đối chiếu, nhưng phần giải thích tập trung vào quan hệ giữa các câu lệnh thay vì lặp lại từng dấu ngoặc, khai báo hoặc phép gán.


### [Dòng 1–16: Giao diện và register](<../../../Verilog%20Source%20code/de_reg.sv#L1>)

<!-- source-range:1:16 -->
```systemverilog
module de_reg(
    input logic clk, rst_n, enable, flush,
    input logic [12:0] instr_de,
    input logic [255:0] reg_out_0_de, reg_out_1_de,
    input logic reg_wr_en_de, mem_wr_en_de, mem_rd_en_de_0, mem_rd_en_de_1,
    input logic [2:0] alu_op_de, input logic wb_sel_de, input logic [8:0] pc_de,
    output logic [12:0] instr_em,
    output logic [255:0] reg_out_0_em, reg_out_1_em,
    output logic reg_wr_en_em, mem_wr_en_em, mem_rd_en_em_0, mem_rd_en_em_1,
    output logic [2:0] alu_op_em, output logic wb_sel_em, output logic [8:0] pc_em
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin instr_em <= 0;reg_out_0_em <= 0;reg_out_1_em <= 0;reg_wr_en_em <= 0;mem_wr_en_em <= 0;mem_rd_en_em_0 <= 0;mem_rd_en_em_1 <= 0;alu_op_em <= 0;wb_sel_em <= 0;pc_em <= 0;end
        else if (enable) begin instr_em <= instr_de;reg_out_0_em <= reg_out_0_de;reg_out_1_em <= reg_out_1_de;reg_wr_en_em <= reg_wr_en_de;mem_wr_en_em <= mem_wr_en_de;mem_rd_en_em_0 <= mem_rd_en_de_0;mem_rd_en_em_1 <= mem_rd_en_de_1;alu_op_em <= alu_op_de;wb_sel_em <= wb_sel_de;pc_em <= pc_de;end
    end
endmodule
```

**Mục đích.** Các suffix của tín hiệu là tên giữ lại từ pipeline cũ. Sự có mặt của file không chứng minh top hiện tại có stage tương ứng.

**Cách phần code hoạt động.** Có logic tuần tự: register/FSM chỉ cập nhật tại cạnh clock; nonblocking assignment đọc giá trị cũ ở vế phải rồi chốt đồng thời.

**Tín hiệu và dữ liệu chính.** `enable`: cho phép pipeline register nhận input; `flush`: xóa payload/control của pipeline register.

