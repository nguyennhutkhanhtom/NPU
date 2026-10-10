# RTL architecture diagrams

<!-- reading-navigation:start -->
[Documentation](../README.md) → [01 · System](../01-system/README.md) → This page

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../00-start-here/fundamentals.md) · [Glossary](../00-start-here/glossary.md) |
| Read first | [Full RTL graph](../source_guide/full_graph.md) |
| Continue / related lookup | [Editable diagram catalog](architecture_catalog.md) |
<!-- reading-navigation:end -->

Current RTL is the source of architectural truth. The redesign replaces all
73 existing Markdown flowcharts with native draw.io pages and linked SVG
previews, and rebuilds both hierarchy files. Historical documents explicitly
label current RTL replacement diagrams; their surrounding prose remains historical.
The legacy software-only NanoFable hybrid flow remains labelled as application context.

| Diagram set | Editable source | Pages |
|---|---|---|
| Module internals, datapaths, host, inference and legacy architecture | [architecture.drawio](architecture.drawio) | 73 |
| llm_soc with USE_QUARTUS_MEMORY=1 | [rtl_hierarchy.drawio](../../rtl_hierarchy.drawio) | 15 |
| llm_soc with USE_QUARTUS_MEMORY=0 | [rtl_hierarchy_portable.drawio](rtl_hierarchy_portable.drawio) | 12 |

Hierarchy containment represents instantiation. Repeated children are aggregated
by module and effective parameters; every covered full instance path is retained
in editable XML metadata and the [manifest](architecture_manifest.json). Coverage
is 749 Quartus / 589 portable instances, including the top. This is elaborated
hierarchy coverage, not synthesized resource usage. Functional arrows represent
data/control dependencies, with explicit parent muxes for shared resources.
Packages are compile-time definitions, not instantiated hardware.

The configured hierarchy uses ATTN_DIV_LANES=4, SIGMOID_LANES=4,
PERF_COUNTERS=0 and ENABLE_DEBUG_INDEX=0. The normalizer uses the parent's
shared divider for lane zero and three private divider instances. Host traffic
uses the RTL request/held-ACK protocol. All sequential full-graph blocks share
clk; u_reset converts raw rst_n into core_rst_n. Stored SRAM contents are unreset.

The visual templates come from all 28 pages of
[Ethos_U85_mini.drawio](../../reference/Ethos_U85_mini.drawio), using legend
cells 00-5/7/9/11/13/15, title 00-2, subtitle 00-3, group 01-7 and open connector
00-32. Blocks are square and colored by function; connectors are orthogonal.
Text uses 12 px blocks, 11 px signal labels and 20 px titles. The requested
CODEX_DRAWIO_STYLE_GUIDE.md filename is absent; [diagram_style.md](diagram_style.md)
contains that guide and was used unchanged.

Architectural corrections include four-result continuous linear streaming,
eight-result vocabulary streaming and packed scale reads, nine linear and six
head tag stages through the parent scalar registers, aligned upper scalar
partials, exact memory backend/latency branches, and separation of private
ternary arithmetic from shared SIMD. Parent token storage is a register array,
not an invented output SRAM module. Legacy reduction diagrams include the
registered S14 total, and acc_mul uses growing, capped level widths.

[Structural validation](architecture_validation.json) checks XML/editability,
instance coverage, source hashes and port names/directions, orthogonal routes,
block/label collisions and source witnesses. [Preview validation](architecture_preview_validation.json)
records local rendering of every page. SVGs use the same native geometry and
labels; diagrams.net desktop CLI is unavailable, so these are local SVG/browser
renders, not diagrams.net exports. No simulation or synthesis was required.

Parameterized widths remain symbolic outside the displayed configurations.
The external altsyncram primitive cannot be inspected internally from repository
RTL. The legacy hierarchy is indexed by instance templates but is not fully
elaborated. No unsupported architectural connection is intentionally represented.

Original draw.io files, SVGs and diagram-bearing Markdown are preserved in
[original_diagrams.zip](../../scratchpad/architecture_redesign/original_diagrams.zip).
RTL/LUT hashes remained unchanged; existing user edits outside diagrams were
preserved. TASK_STATE.md has no diagram status section, so its existing status
fields and other content remain unchanged.

See [rebuild/validation workflow](../../tools/docs/README.md).
