# pipelined_word_ram.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [pipelined_word_ram.sv](<../../../Verilog%20Source%20code/pipelined_word_ram.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Replaceable SRAM adapter. USE_QUARTUS_MEMORY=1 selects 1024-word Quartus tiles when ROWS exceeds 4096, otherwise one whole-bank Quartus leaf. The portable branch uses 1024-word sram_word_tile leaves. Grouped responses preserve three-edge reads for up to four tiles and four-edge reads for larger banks. Writes commit one edge after capture; reset cancels queued enables and validity while preserving storage. |

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
 R["Read / write request"] --> C["Registered address / data / enables"]
 C --> B{"USE_QUARTUS_MEMORY?"}
 B -->|"1 and ROWS above 4096"| T["g_ip_tiled<br/>quartus_word_ram per 1024-word tile"]
 B -->|"1 and ROWS at most 4096"| W["g_ip<br/>One whole-bank quartus_word_ram"]
 B -->|"0"| P["g_model.g_tile<br/>Portable sram_word_tile leaves"]
 T --> G["Registered groups of four tiles"]
 P --> G
 G --> F["Additional response stage<br/>When more than four tiles"]
 W --> O["Read data / matching rd_valid"]
 F --> O
 V["Read-valid pipeline / write pending"] --> A["wr_valid after leaf commit"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class R interface;
class C,G,F,O,V,A buffer;
class B,T,W,P platform;
```
