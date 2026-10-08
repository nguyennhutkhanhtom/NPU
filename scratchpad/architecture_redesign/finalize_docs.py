from pathlib import Path
from collections import Counter
import json,sys,re,zipfile,html,xml.etree.ElementTree as E
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tools/docs'))
import redesign_architecture as a
work=Path(__file__).parent;out=root/'docs/diagrams'
ds=json.loads((work/'routed.json').read_text(encoding='utf-8'));man=json.loads((out/'architecture_manifest.json').read_text())
with zipfile.ZipFile(work/'original_diagrams.zip','a',zipfile.ZIP_DEFLATED) as z:
    names=set(z.namelist())
    for f in ['docs/diagrams/hierarchy_manifest.json','docs/diagrams/preview_validation.json','tools/docs/README.md']:
        if f not in names:z.write(root/f,f)

# Preserve a compact reusable page specification next to the generator. Future
# source changes require review; original Mermaid text is only an inventory.
graphs=json.loads((work/'reviewed_graphs.json').read_text(encoding='utf-8'))
a.save(root/'tools/docs/architecture_pages.json',json.dumps({'source_hashes':man['source_hashes'],'pages':graphs},ensure_ascii=False,indent=2))
catpath=root/'tools/docs/diagram_catalog.json';cat=json.loads(catpath.read_text())
for d in graphs:
    if d['kind']=='functional' and d['index']==1 and d['file'].startswith('docs/source_guide/blocks/') and d['source'] in cat:
        cat[d['source']]['graph']=d['graph']
cat['llm_linear_engine.sv']['summary']='Ordered matrix row stream: two parameter-word credits, four reserved S39 result slots, result_valid/result_ready backpressure, reserved-code faults and cancellation drain. Parent owns tagged scale/RNE/clamp/pack and architectural completion.'
cat['llm_head_engine.sv']['summary']='Ordered 4096-row vocabulary stream: one packed scale read per eight rows, four int8 weight chunks per row and eight reserved S39/U24 results. Parent SIMD issue and six tagged scalar/selection stages preserve row association and PRNG order.'
a.save(catpath,json.dumps(cat,ensure_ascii=False,indent=2))
for name,text in [('llm_linear_engine','The diagram below reflects the matrix stream, two-word credit window and four reserved result slots.'),
                  ('llm_head_engine','The diagram below reflects the vocabulary stream, packed-scale reads and eight backpressured result slots.'),
                  ('llm_soc','The diagrams above reflect continuous row streaming and the tagged scalar epilogue, including the registered upper multiply partial.')]:
    p=root/f'docs/source_guide/blocks/{name}.sv.md';s=p.read_text(encoding='utf-8')
    s=re.sub(r'^Diagram follow-up required:.*$',text,s,flags=re.M);a.save(p,s)
legacy={'date':'2026-10-08','top':'llm_soc','rtl_root':str(root/'Verilog Source code'),
 'scope':'Current reviewed structural expansion. Native pages aggregate identical generated instances; containment means instantiation. Exact paths and port maps remain explicit below.',
 'source_hashes':man['source_hashes'],'source_modules':list(man['modules']),'configurations':{}}
for c,v in man['configurations'].items():
    pages=[d for d in ds if d.get('config')==c]
    legacy['configurations'][c]={'pages':[{'name':d['title'],'id':d['key'],'width':d['width'],'height':d['height']} for d in pages],
        'instances':v['instances'],'counts_by_depth':dict(Counter(r['depth'] for r in v['instances']))}
a.save(out/'hierarchy_manifest.json',json.dumps(legacy,indent=2))
a.save(out/'architecture_catalog.md','# Editable architecture diagram catalog\n\nAll pages use native draw.io shapes and connectors. RTL source is authoritative.\n\n| Page | Source | Editable file | Preview |\n|---|---|---|---|\n'+'\n'.join(
 f'| `{d["key"]}` — {d["title"]} | `{d["source"]}` | [Open]({"../../rtl_hierarchy.drawio" if d.get("config")=="quartus" else "rtl_hierarchy_portable.drawio" if d.get("config")=="portable" else "architecture.drawio"}) | [SVG](previews/{d["key"]}.svg) |' for d in ds))
a.save(out/'README.md','''# RTL architecture diagrams

[Documentation](../README.md) · [All 100 editable pages](architecture_catalog.md)

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
''')
p=root/'tools/docs/README.md';s=p.read_text(encoding='utf-8')
a.save(p,'''# Architecture diagram tooling

The current editable sources are [architecture.drawio](../../docs/diagrams/architecture.drawio),
[Quartus hierarchy](../../rtl_hierarchy.drawio) and
[portable hierarchy](../../docs/diagrams/rtl_hierarchy_portable.drawio).
[architecture_pages.json](architecture_pages.json) is the reviewed page specification,
bound to source hashes. [architecture_manifest.json](../../docs/diagrams/architecture_manifest.json)
indexes all module interfaces and configured instance maps. RTL remains authoritative.

Run from the repository root, using the bundled Python/Node paths if they are not on PATH:

```powershell
python tools/docs/redesign_architecture.py prepare
node tools/docs/layout_architecture.mjs
python tools/docs/redesign_architecture.py emit
python tools/docs/validate_architecture.py
node tools/docs/preview_architecture.cjs
```

The prepare step reuses the reviewed specification only when all RTL/LUT hashes
match. After a source change, first review and update its affected page facts and
source hashes; do not carry old architectural claims forward automatically.
Original diagram files are backed up before replacement. Each native page has
editable boxes, text, parent containers and orthogonal connectors. Native SVG
previews are drawn from those same geometry/labels and rendered in headless Edge.
No RTL, configuration, tests, credentials or external services are modified.

The browser may need to run outside the desktop sandbox. Set DOCS_BROWSER_PATH
to an available headless Chromium browser if the default Edge path is unavailable.
All results and known limitations are in the diagrams README and validation JSONs.

The scripts below describe the retired Mermaid/black-and-white hierarchy workflow.
Its outputs and older dated evidence are historical; running its generators would
replace the redesigned files and is not part of the current workflow.

---

'''+s)

# An actual reference page preview, using its original native geometry/styles.
ref=E.parse(root/'reference/Ethos_U85_mini.drawio').getroot().findall('diagram')[0]
cells=a.model(ref).findall('.//mxCell');items=[]
for c in cells:
    g=c.find('mxGeometry')
    if c.get('vertex')=='1' and g is not None:
        items.append((c,{k:float(g.get(k,'0')) for k in ['x','y','width','height']}))
xmax=max(g['x']+g['width'] for c,g in items)+20;ymax=max(g['y']+g['height'] for c,g in items)+20
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{xmax}" height="{ymax}"><rect width="100%" height="100%" fill="white"/>']
for c,g in items:
    st=dict(x.split('=',1) for x in c.get('style','').split(';') if '=' in x);fill=st.get('fillColor','white');stroke=st.get('strokeColor','black')
    if 'text;' not in c.get('style',''):svg.append(f'<rect x="{g["x"]}" y="{g["y"]}" width="{g["width"]}" height="{g["height"]}" fill="{fill}" stroke="{stroke}"/>')
    label=html.unescape(re.sub(r'<[^>]*>','',c.get('value','')));size=int(st.get('fontSize','12'))
    if label:svg.append(f'<text x="{g["x"]+6}" y="{g["y"]+g["height"]/2+size/3}" font-family="Arial" font-size="{size}" fill="{st.get("fontColor","#111111")}">'+html.escape(label)+'</text>')
a.save(work/'reference_legend.svg','\n'.join(svg+['</svg>']))
print('Catalog, current manifests, diagram follow-ups and workflow synchronized.')
