# matmul_wrap.sv — Wrapper clock/reset/LED

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng nếu chọn board top.

**Source:** [matmul_wrap.sv](<../../../Verilog%20Source%20code/matmul_wrap.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Wrapper đưa CLOCK_50 vào clk và SW[0] vào rst_n của core. LEDG[0]=ready, [1]=overflow, [2]=error. Tín hiệu running/PC/instruction được giữ nội bộ, không đưa ra LED. |

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart LR
CLK["CLOCK_50"] -.-> CORE["matmulfree<br/>NPU core"]
    SW["SW[0] / rst_n"] -.-> CORE
    HOST["Host 32-bit interface"] <--> CORE
    CORE -.-> LED["LEDG[0]=ready<br/>LEDG[1]=overflow<br/>LEDG[2]=error"]
    CORE -.-> DBG["Local signals<br/>running · pc_debug · instr_debug"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

## Main flow

Không có datapath hay chương trình riêng trong wrapper. Host bên ngoài vẫn phải nạp đầy đủ memory/descriptor/program. SW[0]=0 giữ reset; đưa lên 1 mới thoát reset. Khi đóng gói ASIC sẽ cần thay giao diện board phù hợp.

1. Wrapper chỉ nối pin board với core, không thêm datapath hay instruction.
2. CLOCK_50 cấp trực tiếp cho core; SW[0] là reset active-low.
3. Host bus đi thẳng vào matmulfree nên giữ nguyên memory map và quy tắc chỉ ghi khi idle.
4. LED báo ready, overflow và error; running/PC/instruction debug chỉ tồn tại nội bộ.

## Important state / datapath groups

### [Dòng 1–14: Port và debug nội bộ](<../../../Verilog%20Source%20code/matmul_wrap.sv#L1>)

**Mục đích.** Tên clock theo board không phải tần số timing signoff.

**Cách phần code hoạt động.** Nhóm này định nghĩa giao diện, độ rộng, kiểu hoặc tín hiệu trung gian. Nó tạo cấu trúc để các nhóm xử lý sau sử dụng, chưa tự biểu diễn một bước runtime riêng.

**Tín hiệu và dữ liệu chính.** `CLOCK_50`: clock từ board wrapper; `SW`: switch0 dùng làm rst_n; `LEDG`: ba LED chỉ ready/overflow/error; `host_en`: host đang yêu cầu truy cập; `host_we`: host chọn ghi thay vì đọc; `host_addr`: địa chỉ phía host; và 6 tín hiệu phụ khác trong đoạn code.

### [Dòng 15–29: Instance core](<../../../Verilog%20Source%20code/matmul_wrap.sv#L15>)

**Mục đích.** Named ports đưa host thẳng vào matmulfree và status đến LED.

**Cách phần code hoạt động.** Có instance module con; named-port ở nhóm này xác định chính xác đường control/data giữa hai cấp hierarchy.

**Tín hiệu và dữ liệu chính.** `CLOCK_50`: clock từ board wrapper; `SW`: switch0 dùng làm rst_n; `host_en`: host đang yêu cầu truy cập; `host_we`: host chọn ghi thay vì đọc; `host_addr`: địa chỉ phía host; `host_wdata`: data 32 host muốn ghi; và 9 tín hiệu phụ khác trong đoạn code.
