# llm_head_engine.sv

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams use the [shared visual style](../../diagrams/diagram_style.md).
[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)

**Source:** [llm_head_engine.sv](<../../../Verilog%20Source%20code/llm_head_engine.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Stream all 4,096 vocabulary rows in one pass. Each eight-row group reads its packed scale word, then four int8 weight words per row, with at most eight reads outstanding. Weight responses request parent operand capture and shared SIMD issue; four ordered sums form each S39 row result, which retires with its U24 scale. The parent owns RNE, noise, PRNG order and token selection. |
| Ordering | Responses and SIMD sums return in issue order. Two scale slots alternate by group; a group's scale response follows the previous group's 32 weight responses, so the slot it overwrites belongs to a group that has already retired. |
| Cancel / reset | `cancel_i` stops requests, captures and retirement, then `DRAIN` waits for every accepted read and SIMD sum before `busy_o` falls. Reset clears state and validity; scale and accumulator payloads are unreset. |

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
 S["start_i"] --> C["IDLE / RUN / DRAIN<br/>Request, response, sum counters"]
 C --> P["Ordered read stream<br/>scale word, then 4 weight words/row"]
 P --> M["Parent parameter SRAM<br/>≤8 reads outstanding"]
 M -->|"scale word"| SC["Two scale slots<br/>8 × U24 per group"]
 M -->|"weight word"| O["Parent operand capture<br/>math issue next edge"]
 O --> SIMD["Parent shared u_math"]
 SIMD -->|"sum_valid_i / sum_i"| A["S39 row accumulator<br/>retire after fourth sum"]
 SC --> A
 A --> OUT["Row result + U24 scale<br/>parent epilogue"]
classDef control fill:#f8cecc,stroke:#b85450,color:#111111;
classDef interface fill:#fff2cc,stroke:#d6b656,color:#111111;
classDef buffer fill:#f5f5f5,stroke:#666666,color:#111111;
classDef compute fill:#b1ddf0,stroke:#10739e,color:#111111;
classDef output fill:#dae8fc,stroke:#6c8ebf,color:#111111;
classDef platform fill:#e1d5e7,stroke:#9673a6,color:#111111;
class C control;
class S,O,SIMD,SC buffer;
class P,A compute;
class OUT output;
class M platform;
```
