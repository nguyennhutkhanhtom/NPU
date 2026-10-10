# Codex Guide — Create Architecture Diagrams in the Style of `Ethos_U85_mini.drawio`

<!-- reading-navigation:start -->
[Documentation](../README.md) → [Decisions](../decisions/README.md) → This page

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../00-start-here/fundamentals.md) · [Glossary](../00-start-here/glossary.md) |
| Read first | [Diagram index](README.md) |
| Continue / related lookup | [Editable diagram catalog](architecture_catalog.md) |
<!-- reading-navigation:end -->

> **Purpose:** Help Codex create or modify **editable diagrams.net / draw.io (`.drawio`) architecture block diagrams** that visually match `Ethos_U85_mini.drawio`.
>
> **Reference file:** `Ethos_U85_mini.drawio` (required; place it in the workspace or supply its exact path).
>
> **Scope:** Layout, grouping, typography, symbols, fills, borders, connectors, bus labels, and visual consistency. Use the reference for *appearance*, and the user's RTL/specification for *design facts*.

## 1. Non-negotiable instructions

1. **Open and inspect the actual reference file first.** Do not invent a palette, font size, shape style, arrowhead type, or layout convention and claim it came from the reference.
2. **Preserve editability:** generate native draw.io XML (`mxfile`, `diagram`, `mxGraphModel`, `mxCell`, `mxGeometry`); never substitute a screenshot, PNG, SVG image embedded in a canvas, or Mermaid export for the requested editable diagram.
3. **Match the reference before beautifying.** Prefer copying exact `style` strings and reusing representative shapes/containers from the original over applying an unrelated modern design theme.
4. **Separate facts from appearance:** hardware blocks, hierarchy, ports, clock/reset domains, signal directions, and connectivity must come from the provided RTL/spec; the reference diagram supplies visual conventions only. Never infer a signal connection merely because two boxes are adjacent.
5. **Do not modify the reference by default.** Save the output as a separate `<design_name>.drawio`; only edit the reference if explicitly requested.
6. **No cosmetic changes to functional meaning:** do not silently omit blocks, reverse signal direction, invent bus widths, merge clock domains, or relabel interfaces.
7. **When the reference is missing or unreadable, stop claiming a style match.** Report the blocker and either ask for the file or produce an explicitly labeled provisional diagram.

## 2. First task: extract the *real* reference style

Inspect all `<diagram>` pages, not just the first page. diagrams.net may store page data as either uncompressed `<mxGraphModel>` children or compressed Base64 + raw DEFLATE text.

Run this read-only inventory script in the directory containing the reference. It prints actual style frequencies, representative labels and sizes, and edge/vertex counts. Use it to discover the reference; **do not treat the printed top styles as universal rules without checking their visual roles.**

```python
# Save temporarily as inspect_drawio.py, or run inside a Python session.
from collections import Counter
from pathlib import Path
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import zlib

reference = Path('Ethos_U85_mini.drawio')
mxfile = ET.parse(reference).getroot()


def get_model(diagram):
    model = diagram.find('mxGraphModel')
    if model is not None:
        return model
    encoded = (diagram.text or '').strip()
    if not encoded:
        raise ValueError('No mxGraphModel / encoded data in diagram')
    # diagrams.net compressed format = URL-encoded XML + raw DEFLATE + Base64.
    decoded = base64.b64decode(encoded)
    xml_text = urllib.parse.unquote(zlib.decompress(decoded, -15).decode('utf-8'))
    return ET.fromstring(xml_text)


for index, page in enumerate(mxfile.findall('diagram'), 1):
    model = get_model(page)
    cells = model.findall('.//mxCell')
    vertices = [c for c in cells if c.get('vertex') == '1']
    edges = [c for c in cells if c.get('edge') == '1']
    print(f'\nPAGE {index}: {page.get("name", "(unnamed)")}')
    print('vertices:', len(vertices), '| edges:', len(edges))
    for kind, group in [('VERTEX', vertices), ('EDGE', edges)]:
        print('\n', kind, 'TOP STYLES:')
        for style, count in Counter(c.get('style', '') for c in group).most_common(12):
            print(f'  {count:4d}  {style[:220]}')
        print(kind, 'REPRESENTATIVE OBJECTS:')
        seen_styles = set()
        for c in group:
            style = c.get('style', '')
            if style in seen_styles:
                continue
            seen_styles.add(style)
            geom = c.find('mxGeometry')
            size = '' if geom is None else f"{geom.get('width','?')}x{geom.get('height','?')}"
            label = c.get('value', '')[:85].replace('\n', ' ')
            print('  ', c.get('id'), '|', size, '|', repr(label))
            if len(seen_styles) >= 16:
                break
```

**Also examine the rendered original**, if a diagram editor or renderer is available. XML style frequency alone cannot tell whether a shape serves as a title, top-level system boundary, subgroup, functional block, port, annotation, or interface bus.

Record the observations before drawing:

| Visual element | What Codex must extract from the reference |
|---|---|
| Canvas / pages | page size or aspect ratio, page margins, number of pages, background |
| Top-level boundaries | `style`, geometry, fill, stroke, title/header placement |
| Subsystem containers | outline style, nesting convention, padding, header location |
| Functional blocks | typical dimensions, fill, border, corner radius, text alignment |
| Small blocks / IP macros | sizing conventions and how they differ from major blocks |
| Interface / port labels | label placement, font, text rotation, anchoring |
| Data/control connections | `edgeStyle`, stroke color/width, arrowheads, line pattern |
| Bus connections | thickness, naming, whether a shared bus/backbone is used |
| Clock/reset paths | styling, explicit source/sink labels, domain boundary convention |
| Typography | `fontFamily`, `fontSize`, boldness, font color, line-height |
| Geometry | grid size, minimum spacing, alignment, preferred flow direction |

Where styles vary by role, build a **role → exact template style** mapping, rather than one style for all boxes.

## 3. Layout rules

- Organize the drawing by the **actual hardware hierarchy**: system → subsystem → functional block → interface / signal. A visual grouping must correspond to a real architectural grouping.
- Follow the reference's dominant information flow (left-to-right or top-to-bottom) and grouping pattern. Place producer, interconnect, consumer, memory, and peripherals according to the real design.
- Reuse the reference's level of detail. Do not make a high-level architecture diagram look like a transistor schematic, or overload it with individual handshake bits when the reference uses interface-level labels.
- Keep parent containers behind their children, with consistent inner padding. Avoid overlap, clipped text, and blocks spilling beyond their parents.
- Keep blocks on a consistent grid. Where the source has regular rows/columns, reproduce that alignment and the relative proportions of its main blocks.
- Prefer clear orthogonal (horizontal/vertical) routing for block diagrams, **unless the reference consistently uses a different routing style**.
- Route lines to visible connection points or explicit source/target vertices. Avoid lines passing through unrelated blocks and crossing labels.
- Keep fan-in/fan-out, branching, and shared backbones understandable. Use line junctions only when the connectivity is real; crossing lines must not imply connection by accident.
- Use concise, legible labels. Use exact module, protocol, interface, and signal names from sources; preserve capitalization and widths. Avoid visually ambiguous abbreviations.
- Match whitespace density to the reference. Expand the canvas when necessary; do not shrink all labels to force the drawing into a fixed rectangle.

## 4. Hardware-specific semantic rules

These are **correctness requirements**, not claims about specific contents of `Ethos_U85_mini.drawio`.

- Distinguish **data paths**, **control paths**, **clock/reset**, and **status/interrupt paths** where the source information and reference style make this meaningful.
- For **AXI/APB or other bus interfaces**, show the bus direction and protocol at the correct abstraction level. If channels are shown individually, preserve each channel's correct direction (e.g. AXI responses return toward the requester).
- For **multiple clock domains**, mark domain ownership clearly. Show CDC structures only if supported by the actual design. A connector crossing a clock boundary is not a substitute for a correct CDC block.
- For **memory hierarchies**, show controllers, buffers/FIFOs, SRAM/DRAM, and interconnect only to the level that exists in the user's design.
- Do not infer execution units, caches, interconnect fabrics, peripherals, or clock domains from the *reference file's subject matter*; the new design may be different.
- If ports/directions, widths, or module ownership are missing, mark them as `TBD` in an explicit review list; do **not** silently guess.

## 5. How to construct editable draw.io XML

1. **Prefer a template-based approach:** parse the reference and copy the relevant role's exact `mxCell.style`. Copy `mxGeometry` dimensions as a baseline, adapting positions/sizes only where content and readability require it.
2. Create a valid `mxfile` containing at least one `diagram` and one `mxGraphModel/root`. A new model needs root cells with IDs `0` and `1` (layer with `parent="0"`).
3. For every new cell, assign a **unique ID**. Use `vertex="1"` for boxes and labels; use `edge="1"` for connections.
4. Set box geometry using `<mxGeometry x="..." y="..." width="..." height="..." as="geometry"/>`. For edges, use `<mxGeometry relative="1" as="geometry"/>`, with source/target points or intermediate waypoints where required.
5. Match the reference's container hierarchy using `parent`. Be aware: children's coordinates are generally **relative to their parent container**, not necessarily absolute on the page.
6. Connect edges using `source` and `target` vertex IDs where possible. For multi-port and multi-edge shapes, specify entry/exit anchor settings from the reference's connector style as appropriate.
7. Reuse exact source styles for matching semantic roles. Only adjust the minimum necessary parameters (e.g. orientation or edge endpoint) when the design requires them.
8. Escape text safely by serializing with an XML library. Draw.io may contain HTML labels; preserve supported formatting from the reference, but don't double-escape entities.
9. Save as **uncompressed, editable XML** unless compressed output is explicitly necessary. diagrams.net opens uncompressed `<mxGraphModel>` normally.
10. If reusing existing cells, re-map all copied IDs and references (`id`, `parent`, `source`, `target`) consistently; never leave a link pointing at an old or non-existent shape.

Minimal structural illustration **only** (not a style template):

```xml
<mxfile host="app.diagrams.net">
  <diagram name="Architecture" id="architecture-page">
    <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" page="1">
      <root>
        <mxCell id="0" />
        <mxCell id="1" parent="0" />
        <mxCell id="block_a" value="Block A" style="STYLE_COPIED_FROM_REFERENCE" vertex="1" parent="1">
          <mxGeometry x="80" y="80" width="160" height="80" as="geometry" />
        </mxCell>
        <mxCell id="block_b" value="Block B" style="STYLE_COPIED_FROM_REFERENCE" vertex="1" parent="1">
          <mxGeometry x="360" y="80" width="160" height="80" as="geometry" />
        </mxCell>
        <mxCell id="edge_a_b" value="Interface" style="EDGE_STYLE_COPIED_FROM_REFERENCE" edge="1" parent="1" source="block_a" target="block_b">
          <mxGeometry relative="1" as="geometry" />
        </mxCell>
      </root>
    </mxGraphModel>
  </diagram>
</mxfile>
```

**Important:** The placeholders `STYLE_COPIED_FROM_REFERENCE` and `EDGE_STYLE_COPIED_FROM_REFERENCE` must be replaced with styles inspected from the real file. Never ship the illustration itself as the finished output.

## 6. Generate, render, verify, iterate

Perform these checks before declaring completion:

**XML / graph checks**

- The output parses as valid XML and opens in diagrams.net.
- Every shape and edge has a unique ID; every `parent`, `source`, and `target` reference resolves to an existing ID.
- Every visible block/label has intended geometry; parent-relative coordinates are handled correctly.
- The output has no accidentally disconnected edges, unintended duplicates, or stray elements far outside the page.

**Semantic checks**

- Every required module/interface from the source/spec appears exactly at the requested level of detail.
- Connection direction, label, bus grouping, and clock/reset ownership have been verified against the source—not against mere visual proximity.
- Uncertain connections or dimensions are explicitly listed as unresolved; they are not quietly fictionalized.

**Visual checks**

- Export a PNG or SVG preview using diagrams.net desktop CLI **if installed** (for example, `drawio -x -f svg -o output.svg output.drawio`); otherwise open in the editor and inspect there. Do not assume a CLI binary exists.
- Compare the preview side-by-side with the reference at a similar zoom. Verify grouping, stroke/fill palette, label sizing, arrow style, and relative whitespace.
- Correct any overlaps, cropped labels, tangled edges, unclear clock-domain boundaries, or accidental style deviations; render again and repeat until these checks pass.

## 7. Codex reporting and deliverables

When finished, return:

1. `output.drawio` (or the user's requested name): the **editable source diagram**.
2. A brief style audit: which page and example cells supplied the top-level container, block, label, and connector styles.
3. Verification summary: XML validity, successful editor opening/rendering if checked, and any semantic assumptions or still-unknown items.
4. A preview image **only if requested or useful for review**; the preview does not replace the `.drawio` file.

**File safety:** Never overwrite the reference, delete source code, or run destructive shell commands to make a diagram.

## 8. Ready-to-use prompt for Codex

> Read `CODEX_DRAWIO_STYLE_GUIDE.md` and inspect `Ethos_U85_mini.drawio` as the **visual reference**. Analyze its actual `.drawio` XML (including compressed pages if necessary), identify the styles and geometry used by containers, functional blocks, labels, and connectors, then build a new editable diagrams.net architecture drawing for **[DESIGN / RTL FILES / SPEC]**. Match the reference's visual language closely while using only the new design's documented hardware hierarchy and connections. Generate **[OUTPUT_NAME].drawio**, render/inspect the result if possible, validate the graph and XML, and report any uncertain signals separately. Do not modify the reference file.

---

### Reference fidelity note

This guide intentionally does **not** hard-code a guessed palette or claim specific colors, sizes, or shapes were observed in the uploaded example. Codex must extract those properties from `Ethos_U85_mini.drawio` in its own workspace before creating a matching diagram. If a visually exact match is required, keep the `.drawio` reference beside this guide.
