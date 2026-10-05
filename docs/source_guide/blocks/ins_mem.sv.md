# ins_mem.sv — Instruction RAM và fetch/host valid

[Tài liệu](../../README.md) → [Hierarchy RTL](../README.md) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng.

**Source:** [ins_mem.sv](<../../../Verilog%20Source%20code/ins_mem.sv>). **Số dòng:** 61. **SHA-256:** `d33ef061d5517a0a21e75e13be3b68cde82b7214f9964b81711e9f7d53751123`.

## Khối này làm gì?

Memory 512×13 bit do host nạp, không reset hoặc initialize nội dung. Một cổng đọc đồng bộ dùng chung cho fetch và host có tag/valid; top chặn host khi running và scheduler chờ `instr_valid`. Simulation và synthesis dùng cùng RTL và cùng latency, không phụ thuộc define hoặc thuộc tính memory của hãng. Reset chỉ xóa control/tag; host phải nạp chương trình hợp lệ và HALT trước khi start.

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
H["Host: en / we / addr / write instruction"]
    F["Scheduler: fetch_en / PC"]
    subgraph IM["ins_mem"]
        MUX@{ shape: trap-t, label: "Shared read address selector<br/>Host read or fetch" }
        REQ["Request registers<br/>address / client / pending"]
        RAM@{ shape: rect, label: "Instruction memory<hr/>512 × 13 bit<hr/>Synchronous read / host write" }
        DATA["Read data register 13 bit<br/>No asynchronous reset"]
        RESP["Response registers<br/>address / client / valid"]
        MATCH["Current request + two tags match<br/>Client / address / read enabled"]
    end
    H -.-> MUX
    F -.-> MUX
    MUX -.-> REQ
    REQ -.-> RAM
    H -->|"Write"| RAM
    RAM --> DATA
    REQ -.-> RESP
    H -.-> MATCH
    F -.-> MATCH
    REQ -.-> MATCH
    RESP -.-> MATCH
    DATA -->|"instr 13 bit"| F
    DATA -->|"host_rinstr 13 bit"| H
    MATCH -.->|"instr_valid"| F
    MATCH -.->|"host_rvalid → frontend response register"| H
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

Nét liền là dữ liệu, nét đứt là điều khiển và địa chỉ. Memory và read data register không có reset bất đồng bộ. Sơ đồ mô tả storage logic, không quy định macro vật lý.

## Cách hoạt động chi tiết

1. Host write tại cạnh lên khi rst_n, host_en và host_we. Top chỉ chấp nhận khi core idle.
2. Một request read ổn định qua hai cạnh lên: cạnh đầu chốt address/client, cạnh thứ hai chốt RAM data và response tag. Valid chỉ lên khi request hiện tại, request tag và response tag cùng địa chỉ/client.
3. Fetch valid chỉ có khi fetch_en đang giữ. Scheduler ở S_FETCH đến khi valid rồi chốt instr_q ở cạnh tiếp theo. Fetch dùng cùng hai cạnh lên của hợp đồng bộ nhớ trong mọi build.
4. Cổng host của RAM giữ en, we=0 và address đến host_rvalid; frontend top chốt request/response rồi trả host_ready sau bốn cạnh lên cho host ngoài. Write, idle hoặc đổi client làm response cũ mất hiệu lực; đọc lại cùng địa chỉ sau write vẫn phải chờ.
5. Memory và read data register không reset; reset xóa tag/control nên response trước reset mất hiệu lực. Không được dùng data khi valid=0.
6. Test độc lập kiểm tra toàn bộ 512 địa chỉ, chuyển client, overwrite/re-read, restart cùng PC và reset không xóa contents. Test top đi đến PC=511, restart và lỗi khi chương trình cố đi qua PC cuối.

## Các nhóm logic trong source

Các đoạn dưới đây bao phủ nguyên văn toàn bộ source hiện tại, theo thứ tự dòng.

### [Dòng 1–19: Giao diện, memory và tag registers](<../../../Verilog%20Source%20code/ins_mem.sv#L1>)

<!-- source-range:1:19 -->
```systemverilog
module ins_mem (
    input logic clk,
    input logic rst_n,
    input logic fetch_en,
    input logic [8:0] addr,
    output logic [12:0] instr,
    output logic instr_valid,
    input logic host_en,
    input logic host_we,
    input logic [8:0] host_addr,
    input logic [12:0] host_instr,
    output logic [12:0] host_rinstr,
    output logic host_rvalid
);

    logic [12:0] mem [0:511];
    logic [12:0] read_data_q;
    logic [8:0] read_address_q, response_address_q;
    logic read_pending_q, read_host_q, response_host_q, read_valid_q;
```

**Mục đích.** Địa chỉ U9 chọn một trong 512 instruction 13 bit. Hai client có enable/valid riêng nhưng chia sẻ memory và read data register. Tag chứa địa chỉ/client để response chỉ acknowledge đúng request hiện tại.

### [Dòng 20–28: Host write và đọc memory đồng bộ](<../../../Verilog%20Source%20code/ins_mem.sv#L20>)

<!-- source-range:20:28 -->
```systemverilog

    // Host and fetch share one synchronous read port. Neither RAM nor its
    // output register has an asynchronous reset or initialization loop.
    always_ff @(posedge clk) begin
        if (rst_n && host_en && host_we)
            mem[host_addr] <= host_instr;
        if (read_pending_q)
            read_data_q <= mem[read_address_q];
    end
```

**Cách hoạt động.** Host write được chốt tại cạnh lên khi reset đã nhả và request write hợp lệ. Read dùng địa chỉ chốt ở cạnh trước; `read_pending_q` bật capture dữ liệu. Memory không initialize hoặc reset, read data register không asynchronous reset.

### [Dòng 29–37: Dữ liệu chung và valid theo client](<../../../Verilog%20Source%20code/ins_mem.sv#L29>)

<!-- source-range:29:37 -->
```systemverilog

    assign instr = read_data_q;
    assign host_rinstr = read_data_q;
    assign instr_valid = fetch_en && read_valid_q && !response_host_q &&
        read_pending_q && !read_host_q &&
        read_address_q == addr && response_address_q == addr;
    assign host_rvalid = host_en && !host_we && read_valid_q && response_host_q &&
        read_pending_q && read_host_q &&
        read_address_q == host_addr && response_address_q == host_addr;
```

**Cách hoạt động.** Cùng `read_data_q` lái cả output instruction. Valid chọn client phù hợp và yêu cầu hai tag cùng địa chỉ hiện tại. Fetch valid còn yêu cầu `fetch_en`; host valid yêu cầu read đang giữ. Data có thể còn giá trị cũ nhưng không được tiêu thụ khi valid=0.

### [Dòng 38–61: Chốt request, chuyển response và reset](<../../../Verilog%20Source%20code/ins_mem.sv#L38>)

<!-- source-range:38:61 -->
```systemverilog

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            read_address_q <= '0;
            response_address_q <= '0;
            read_pending_q <= 1'b0;
            read_host_q <= 1'b0;
            response_host_q <= 1'b0;
            read_valid_q <= 1'b0;
        end else begin
            read_valid_q <= read_pending_q;
            response_host_q <= read_host_q;
            response_address_q <= read_address_q;
            read_pending_q <= fetch_en || (host_en && !host_we);
            if (host_en && !host_we) begin
                read_address_q <= host_addr;
                read_host_q <= 1'b1;
            end else if (fetch_en) begin
                read_address_q <= addr;
                read_host_q <= 1'b0;
            end
        end
    end
endmodule
```

**Cách hoạt động.** Reset chỉ xóa control/tag. Cạnh lên chuyển request tag sang response và lấy request host read hoặc fetch mới. Khi request đổi địa chỉ hoặc client, response cũ không khớp nên phải đợi đủ hai cạnh lên. Top giữ host và fetch loại trừ nhau; priority host trong mux không tạo một cổng đọc thứ hai.
