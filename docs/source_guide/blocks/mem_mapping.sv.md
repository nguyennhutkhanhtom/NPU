# mem_mapping.sv — Wrapper SRAM 32 KiB

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng.

**Source:** [mem_mapping.sv](<../../../Verilog%20Source%20code/mem_mapping.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | File này giữ interface riêng cho parameter memory nhưng dùng chung `sram_256_wrapper` với ADDR_W=10. Module có tên `mem_mapping`; đường compute của instance trong top chỉ đọc; host nạp weight/bias qua cổng32 bit. |

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart LR
C["Ternary compute read port<br/>Data 256 bit · address 10 bit<br/>Compute write tied off in matmulfree"]
    H["Host port<br/>Data 32 bit · word-index 13 bit"]
    subgraph WRAP["mem_mapping"]
        subgraph SRAM["sram_256_wrapper · ADDR_W=10"]
            PORT["Masked write / shared synchronous read<br/>Host lane select + host_rvalid"]
            MEM@{ shape: rect, label: "Parameter memory array<hr/>1024 × 256 bit<hr/>8 bank × 32 bit<hr/>32 KiB" }
            PORT <--> MEM
        end
    end
    C -.->|"Read request"| PORT
    PORT -->|"Read data / valid"| C
    H <-->|"32-bit lane access + host_rvalid"| PORT
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

## Main flow

Compute đọc/ghi word 256; host chọn một slice32. Wrapper không thêm FSM hay đổi latency. Mỗi port được nối một-một vào implementation chung; xem sram_256_wrapper để hiểu timing và write mask.

1. Đây là wrapper parameter SRAM 32 KiB: compute address 10 bit chọn 1024 word, host thêm ba bit lane.
2. Trong top, compute write bị buộc zero nên ternary core chỉ đọc; host nạp weight/bias khi idle.
3. Tín hiệu nối trực tiếp vào wrapper chung; module không còn mapping FIFO/vector kiểu thesis.
4. Adapter SRAM macro phải giữ read-valid contract mà ternary core đang chờ.

**Quy ước RTL.** Wrapper nối `host_rvalid` từ SRAM lên top. Backend nhận read/address từ frontend và trả host_rvalid sau hai cạnh lên. Frontend top chốt request/response, nên host ngoài giữ read/address bốn cạnh lên đến host_ready. Memory có tám bank 32 bit, write-enable riêng từng lane. Wrapper chỉ nối cổng, không thêm register hoặc đổi latency. Simulation và synthesis dùng cùng hợp đồng memory. Xem [implementation và sơ đồ SRAM](sram_256_wrapper.sv.md).

## Important state / datapath groups

### [Dòng 1–21: Hai giao diện](<../../../Verilog%20Source%20code/mem_mapping.sv#L1>)

**Mục đích.** Địa chỉ compute đếm word 256, host đếm word 32. Host address byte đã được top bỏ hai bit alignment.

**Cách phần code hoạt động.** Nhóm này định nghĩa giao diện, độ rộng, kiểu hoặc tín hiệu trung gian. Nó tạo cấu trúc để các nhóm xử lý sau sử dụng, chưa tự biểu diễn một bước runtime riêng.

**Tín hiệu và dữ liệu chính.** `rd_en`: request đọc của compute; `rd_addr`: địa chỉ word cần đọc; `rd_data`: word dữ liệu đọc ra; `rd_valid`: response đọc hợp lệ; `wr_en`: cho phép ghi compute; `wr_addr`: địa chỉ word cần ghi; và 6 tín hiệu phụ khác trong đoạn code.

### [Dòng 22–40: Instance SRAM](<../../../Verilog%20Source%20code/mem_mapping.sv#L22>)

**Mục đích.** Parameter ADDR_W quyết định depth; các named port nối trực tiếp cùng chức năng.

**Cách phần code hoạt động.** Có instance module con; named-port ở nhóm này xác định chính xác đường control/data giữa hai cấp hierarchy.

**Tín hiệu và dữ liệu chính.** `rd_en`: request đọc của compute; `rd_addr`: địa chỉ word cần đọc; `rd_data`: word dữ liệu đọc ra; `rd_valid`: response đọc hợp lệ; `wr_en`: cho phép ghi compute; `wr_addr`: địa chỉ word cần ghi; và 6 tín hiệu phụ khác trong đoạn code.
