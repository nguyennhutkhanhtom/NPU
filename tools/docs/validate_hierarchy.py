"""Validate diagram XML, source linkage, preview evidence and preserved RTL."""
from pathlib import Path
from hashlib import sha256
from collections import Counter
import json, re
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/diagrams'
AUDIT=ROOT/'docs/verification/diagrams_20261006'
manifest=json.loads((OUT/'hierarchy_manifest.json').read_text())
before=json.loads((AUDIT/'before.json').read_text())
errors=[];reports=[]
for name,expected in before['rtl'].items():
    if sha256((ROOT/'Verilog Source code'/name).read_bytes()).hexdigest()!=expected:
        errors.append('RTL changed: '+name)
for name,expected in manifest['source_hashes'].items():
    if sha256((ROOT/'Verilog Source code'/name).read_bytes()).hexdigest()!=expected:
        errors.append('Stale hierarchy source: '+name)
for config,file in [('quartus',ROOT/'rtl_hierarchy.drawio'),('portable',OUT/'rtl_hierarchy_portable.drawio')]:
    data=manifest['configurations'][config];records={r['path']:r for r in data['instances']}
    tree=ET.parse(file);pages=tree.findall('diagram');expected_names=[p['name'] for p in data['pages']]
    if [p.get('name') for p in pages]!=expected_names:errors.append('Page order: '+config)
    for depth,page in enumerate(pages):
        cells=page.findall('.//mxCell');vertices=[c for c in cells if c.get('vertex')=='1']
        modcells=[c for c in vertices if c.get('rtlPath')];paths={c.get('rtlPath') for c in modcells}
        current={p for p,r in records.items() if r['depth']==depth}
        parents={records[p]['parent'] for p in current if records[p]['parent']}
        if paths!=current|parents:errors.append('Instance coverage: '+config+':'+str(depth))
        functions=[c for c in vertices if c.get('value','').startswith('Block Functions & Interfaces')]
        if len(functions)!=1:errors.append('Function panel: '+config+':'+str(depth))
        for c in cells:
            if c.get('vertex')=='1' or c.get('edge')=='1':
                style=c.get('style','')
                if 'fontSize=24;' not in style:errors.append('Font size: '+config+':'+c.get('id'))
                for key,color in re.findall(r'(fillColor|strokeColor|fontColor)=([^;]+)',style):
                    if color not in {'#ffffff','#000000','none'}:errors.append('Color: '+config+':'+c.get('id'))
        for c in modcells:
            r=records[c.get('rtlPath')]
            if c.get('value')!=r['name']+'\n('+r['module']+')':errors.append('Two-line label: '+r['path'])
            if ('dashed=1;' in c.get('style',''))!=r['external']:errors.append('External outline: '+r['path'])
            if not r['external']:
                source=(ROOT/'Verilog Source code'/r['module_source']).read_text(encoding='utf-8-sig').splitlines()
                if not re.search(r'\bmodule\s+'+re.escape(r['module'])+r'\b',source[r['module_line']-1]):errors.append('Module reference: '+r['path'])
            if r['parent']:
                source=(ROOT/'Verilog Source code'/r['instantiation_source']).read_text(encoding='utf-8-sig').splitlines()
                if not re.search(r'\b'+re.escape(r['module'])+r'\b',source[r['instantiation_line']-1]):errors.append('Instance reference: '+r['path'])
        byid={c.get('id'):c for c in cells}
        for e in (c for c in cells if c.get('edge')=='1'):
            a=byid[e.get('source')].get('rtlPath');b=byid[e.get('target')].get('rtlPath')
            if 'strokeWidth=1;' in e.get('style','') and records[b]['parent']!=a:errors.append('Parent arrow: '+config+':'+b)
        reports.append({'configuration':config,'page':page.get('name'),'instance_blocks':len(modcells),
                        'current_depth_instances':len(current),'context_instances':len(parents)})
preview=json.loads((OUT/'preview_validation.json').read_text())
if len(preview['pages'])!=9:errors.append('Preview coverage')
for p in preview['pages']:
    if p['errors'] or p['fonts']!=['24px']:errors.append('Preview layout: '+p['file'])
mermaid=json.loads((ROOT/'docs/source_guide/diagram_validation.json').read_text())
for d in mermaid['diagrams']:
    if d['status']!='rendered' or d.get('layout_errors') or d.get('fonts')!=['24px'] or d.get('text_colors')!=['rgb(0, 0, 0)']:
        errors.append('Mermaid layout/style: '+d['file']+':'+str(d['ordinal']))
frozen=[p for p in before['documents'] if p.startswith('docs/verification/') or p=='docs/history/task_state_20261004.md']
for p in frozen:
    if sha256((ROOT/p).read_bytes()).hexdigest()!=before['documents'][p]:errors.append('Frozen document changed: '+p)
result={'date':'2026-10-06','status':'PASS' if not errors else 'FAIL','top':'llm_soc','source_assets_checked':len(before['rtl']),
        'rtl_unchanged':not any('RTL changed' in e for e in errors),'frozen_documents_checked':len(frozen),
        'mermaid_diagrams_rendered':len(mermaid['diagrams']),'hierarchy_pages_rendered':len(preview['pages']),
        'pages':reports,'errors':errors,
        'visual_review':'All six Mermaid contact sheets inspected; hierarchy top, structural levels, functional connectors, generated scope labels and function panels inspected in rendered viewport bands. XML and SVG share label/geometry generation; no native diagrams.net editor screenshot was used.',
        'limitations':'Configuration-specific reviewed expansion, not a general SV elaborator or synthesis check. Hierarchy depth pages intentionally retain every instance and require zoom/scroll at deep levels. External altsyncram is unresolved repository RTL; only the Quartus variant uses it.'}
(AUDIT/'results.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k not in {'pages','visual_review','limitations'}}))
raise SystemExit(bool(errors))
