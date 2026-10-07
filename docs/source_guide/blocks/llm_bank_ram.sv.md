# llm_bank_ram.sv — SRAM lane-masked cho graph

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)

**Source:** [llm_bank_ram.sv](<../../../Verilog%20Source%20code/llm_bank_ram.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | 32 lane S24 tạo row 768 bit. USE_QUARTUS_MEMORY chọn FPGA IP hoặc model ASIC qua word adapter. Request qua group bốn lane, lane register và adapter register trước storage; read valid năm cạnh với ROWS≤4096, write commit ở cạnh thứ tư. wr_busy buộc operator drain trước completion. Reset hủy queue/valid, giữ storage/payload. |

## Sơ đồ kiến trúc

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
    REQ["Shared row requests"] --> GROUP["Requests per four lanes"]
    MASK["Lane write mask"] --> GROUP
    GROUP --> LOCAL["Per-lane request registers"]
    LOCAL --> BANK["Technology-selected word banks"]
    BANK --> DATA["768-bit row after five edges"]
    MASK --> DRAIN["Four-stage write pending<br/>and wr_busy"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class REQ,GROUP,LOCAL interface;
class MASK,DATA,DRAIN buffer;
class BANK platform;
```

## Important state / datapath groups

### [Dòng 1–24: Interface and write pending](<../../../Verilog%20Source%20code/llm_bank_ram.sv#L1>)

Client dùng rd_valid; operator phải chờ wr_busy hạ trước báo done. Latency bao gồm group, lane và tile stages.

### [Dòng 25–47: Group request distribution](<../../../Verilog%20Source%20code/llm_bank_ram.sv#L25>)

Địa chỉ/data payload chốt không enable mux. SRAM-only dont_merge giữ locality; read/write enables reset để hủy queued requests.

### [Dòng 48–76: Lane banks and response](<../../../Verilog%20Source%20code/llm_bank_ram.sv#L48>)

Leaf old-data collision theo cùng accepted cycle. Lane-valid có cùng latency; output dùng lane0 valid để xác nhận cả row.
