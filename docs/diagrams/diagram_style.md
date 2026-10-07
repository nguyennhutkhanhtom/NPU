## Semantic colors

| Function | Fill | Stroke |
|---|---|---|
| Control / FSM | #f8cecc | #b85450 |
| Interface / transfer | #fff2cc | #d6b656 |
| Buffer / decoder | #f5f5f5 | #666666 |
| Compute / arithmetic | #b1ddf0 | #10739e |
| Activation / output | #dae8fc | #6c8ebf |
| Platform / technology | #e1d5e7 | #9673a6 |

## Connections

- Solid arrow: data/control transfer
- Bidirectional arrow: bidirectional bus
- Dashed arrow: optional/control dependency
- Thick arrow: main flow / loop-back
- Put bus name or width on edge when useful.

## Layout

- Prefer LR for datapath.
- Prefer TB for execution/state flow.
- One abstraction level per diagram.
- Split large diagrams instead of making one huge graph.
- Group related blocks in subgraphs.
- Keep labels short:
  - first line = module/block
  - second line = role, width or capacity

## Markdown

Use Mermaid for Markdown documentation.
Reuse the same classDef palette in every diagram.
Do not invent a different visual style per file.
Diagram rules for Markdown:

Use Mermaid and follow the visual language defined in
docs/diagrams/diagram_style.md.

The goal is architectural readability, NOT reproducing every RTL signal.

IMPORTANT — readability:
- Never create one giant diagram for a complex RTL module.
- If a module has more than ~10 meaningful blocks, split it into multiple diagrams.
- Prefer 2–3 small diagrams:
  1. Module overview
  2. Internal datapath
  3. Control / operation flow, only when useful
- A diagram should remain readable at normal Markdown page width without zooming.
- Avoid ultra-wide diagrams.
- Keep the longest horizontal chain to about 5–7 blocks.
- Prefer TB layout when LR would make the diagram excessively wide.
- Do not nest subgraphs more than one level deep.

Abstraction:
- Show architectural blocks, not individual RTL statements.
- Do NOT draw every internal register, mux, counter, or wire.
- Combine closely related registers into one conceptual block.
  Example:
    q_work + quotient state -> "Quotient state"
    remainder registers -> "Remainder state"
- Show an internal signal only if it is important for understanding:
  - datapath ownership
  - protocol
  - arithmetic width
  - pipeline stage
  - exceptional path
- Do not put trivial control signals such as write_enable,
  select, count==N, etc. on the architecture diagram.
- Explain those details in prose or a table instead.

Edge labels:
- Keep edge labels short.
- Prefer:
    "S24"
    "256-bit weights"
    "req / valid"
    "quotient + remainder"
  instead of full RTL expressions.
- Do not label every edge.
- Only show width when the width is architecturally important.
- Never use long equations as edge labels.
- Put equations or detailed transformations inside the destination block
  or in prose below the diagram.

Node text:
- Maximum ~3 short lines per node.
- First line: block/function name.
- Second line: role or operation.
- Third line: important width/format only if useful.
- Do not put long implementation descriptions inside nodes.
- Prefer conceptual names over raw signal names.

Example:
GOOD:
    "Extended subtract
     rem_shift - den_reg
     DEN_W+2"

AVOID:
    "Extended subtract rem_shift - den_reg difference DEN_W+2"

Layout:
- Inputs should normally enter from the left or top.
- Outputs should leave from the right or bottom.
- Main datapath should have one obvious reading direction.
- Keep control paths visually secondary to the datapath.
- Feedback paths should be routed around the main path when possible.
- Exceptional paths such as divide-by-zero should branch away from the
  normal datapath instead of crossing it.

Semantic palette:
- Control / FSM:
  fill #f8cecc, stroke #b85450
- Interface / transfer:
  fill #fff2cc, stroke #d6b656
- Buffer / register / decoder:
  fill #f5f5f5, stroke #666666
- Compute / arithmetic:
  fill #b1ddf0, stroke #10739e
- Result / normalization / output processing:
  fill #dae8fc, stroke #6c8ebf
- Platform / memory / special shared resource:
  fill #e1d5e7, stroke #9673a6

Connections:
- Solid arrow = main data flow
- Dashed arrow = control/status/optional path
- Bidirectional arrow only for genuinely bidirectional interfaces
- Thick arrow only for an important feedback/main loop
- Avoid crossing edges whenever possible.

Rendering:
- Force a light, documentation-friendly Mermaid theme.
- Do not rely on the viewer's dark/light theme for node colors.
- Use approximately 16–18 px diagram text.
- Use high-contrast dark text.
- Use a white diagram/cluster background.
- Avoid excessive node spacing.

Use this Mermaid initialization unless the document already provides
an equivalent project-wide initialization:

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

For RTL module documentation specifically:

Diagram 1 — Module overview
- Show external inputs/outputs.
- Show 3–7 main internal functional blocks.
- Show normal main data flow.
- Show exceptional path only if architecturally important.
- Do not expose low-level implementation state.

Diagram 2 — Internal datapath
- Show arithmetic transformations and major state/register groups.
- Include important bit widths.
- Do not show external protocol details again.

Diagram 3 — Control/sequence
- Add only when the module has a non-trivial FSM or operation sequence.
- Prefer a compact flowchart/state diagram rather than mixing control
  into the datapath diagram.

Before writing a diagram, ask internally:
"Can a reader understand this at normal GitHub/Markdown width without zooming?"
If not, split or simplify it.

Do not create diagrams merely because RTL contains many signals.
A simpler diagram that explains the architecture is preferred over
a complete wiring diagram.