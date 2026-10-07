# PC.sv — Program counter

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng.

**Source:** [PC.sv](<../../../Verilog%20Source%20code/PC.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | PC 9 bit chọn một trong 512 instruction. Clear đưa về 0, advance tăng1; khi cả hai có hiệu lực, clear ưu tiên. Không có branch/jump trong module này. |

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {
  "theme": "base",
  "themeVariables": {
    "background": "#ffffff",
    "primaryTextColor": "#111111",
    "secondaryTextColor": "#111111",
    "tertiaryTextColor": "#111111",
    "lineColor": "#444444",
    "clusterBkg": "#ffffff",
    "clusterBorder": "#aaaaaa",
    "edgeLabelBackground": "#ffffff",
    "fontSize": "17px"
  },
  "flowchart": {
    "curve": "linear",
    "nodeSpacing": 30,
    "rankSpacing": 40,
    "htmlLabels": true,
    "useMaxWidth": true
  }
}}%%
flowchart TB
CTRL["clear / advance"] -.-> MUX@{ shape: trap-t, label: "Next-PC selector<br/>Zero / increment / hold" }
    ZERO["Constant 0"] --> MUX
    INC["Incrementer +1<br/>9 bit"] --> MUX
    MUX --> REG["PC storage 9 bit"]
    REG --> INC
    REG -->|"Hold feedback"| MUX
    CLK["clk / rst_n"] -.-> REG
    REG --> OUT["pc_out → instruction memory address"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class MUX interface;
class CTRL,ZERO,INC,REG,CLK buffer;
class OUT compute;
```

## Main flow

Reset active-low asynchronous. Clear là điều kiện synchronous tại cạnh clk; advance chỉ được top phát sau instruction hoàn tất. Bản thân phép cộng 9 bit có thể wrap, nhưng scheduler chặn advance tại511.

1. Reset active-low asynchronous đưa PC về zero ngay khi `rst_n=0`.
2. Clear được xét ở cạnh clock và ưu tiên hơn advance; top dùng clear khi start chương trình.
3. Advance tăng PC sau khi instruction hoàn tất. Không có control thì flip-flop giữ giá trị.
4. Phép cộng 9 bit có thể wrap, nhưng top chặn advance tại PC 0x1FF (511).

**Quy ước RTL.** Nhánh `if (!rst_n)` chỉ reset asynchronous; `else if (clear)` là clear synchronous riêng, ưu tiên hơn advance. Không gộp clear vào điều kiện reset bất đồng bộ.

## Important state / datapath groups

### [Dòng 1–7: Giao diện](<../../../Verilog%20Source%20code/PC.sv#L1>)

**Mục đích.** clk/reset và hai control clear/advance.

**Cách phần code hoạt động.** Nhóm này định nghĩa giao diện, độ rộng, kiểu hoặc tín hiệu trung gian. Nó tạo cấu trúc để các nhóm xử lý sau sử dụng, chưa tự biểu diễn một bước runtime riêng.

**Tín hiệu và dữ liệu chính.** `clear`: đưa PC về 0; `advance`: tăng PC lên instruction kế tiếp; `pc_out`: register PC9 bit.

### [Dòng 8–16: Register PC](<../../../Verilog%20Source%20code/PC.sv#L8>)

**Mục đích.** Reset hoặc clear về 0; nếu chỉ advance thì tăng; nếu không có control thì giữ giá trị.

**Cách phần code hoạt động.** Có logic tuần tự: register/FSM chỉ cập nhật tại cạnh clock; nonblocking assignment đọc giá trị cũ ở vế phải rồi chốt đồng thời.

**Tín hiệu và dữ liệu chính.** `clear`: đưa PC về 0; `pc_out`: register PC9 bit; `advance`: tăng PC lên instruction kế tiếp.
