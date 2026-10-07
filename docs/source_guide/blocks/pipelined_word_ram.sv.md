# pipelined_word_ram.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [pipelined_word_ram.sv](<../../../Verilog%20Source%20code/pipelined_word_ram.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Replaceable SRAM adapter. USE_QUARTUS_MEMORY=1 selects 1024-word Quartus tiles when ROWS exceeds 4096, otherwise one whole-bank Quartus leaf. The portable branch uses 1024-word sram_word_tile leaves. Grouped responses preserve three-edge reads for up to four tiles and four-edge reads for larger banks. Writes commit one edge after capture; reset cancels queued enables and validity while preserving storage. |

## Sơ đồ kiến trúc

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
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
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```
