from pathlib import Path
import hashlib, html, json, os, re
from urllib.parse import unquote

ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
manifest=json.loads((OUT/'source_manifest.json').read_text(encoding='utf-8'))
errors=[]
total=0
rtl_group_count=0
rtl_grouped_lines=0
main_diagrams=0
detail_diagrams=0
for entry in manifest['files']:
    source=(ROOT/entry['path']).resolve()
    raw=source.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=entry['sha256']:
        errors.append(f'Source changed: {source.name}')
    try: lines=raw.decode('utf-8-sig').splitlines()
    except UnicodeDecodeError: lines=raw.decode('gb18030',errors='replace').splitlines()
    if len(lines)!=entry['lines']:
        errors.append(f'Manifest line count mismatch: {source.name}')
    doc=(OUT/entry['document']).read_text(encoding='utf-8')
    header=re.search(r'\*\*Số dòng:\*\* (\d+)\. \*\*SHA-256:\*\* `([a-f0-9]+)`',doc)
    if not header or int(header[1])!=len(lines) or header[2]!=entry['sha256']:
        errors.append(f'Document source header mismatch: {source.name}')
    if source.suffix.lower() in ['.sv','.v']:
        count=doc.count('```mermaid')
        main_diagrams+=1 if count>=1 else 0
        detail_diagrams+=max(0,count-1)
        if count<1: errors.append(f'Missing block Mermaid diagram: {source.name}')
        if '## Cách hoạt động chi tiết' not in doc:
            errors.append(f'Missing detailed operation section: {source.name}')
        if '| Dòng | Code gốc | Giải thích |' in doc:
            errors.append(f'Per-line table remains in RTL guide: {source.name}')
        groups=re.findall(r'<!-- source-range:(\d+):(\d+) -->\r?\n```systemverilog\r?\n(.*?)\r?\n```',doc,re.S)
        headings=re.findall(r'^### \[Dòng (\d+)–(\d+): .*?\]\(<[^>]+#L(\d+)>\)',doc,re.M)
        if [(a,b,a) for a,b,_ in groups]!=headings:
            errors.append(f'Group heading/line link mismatch: {source.name}')
        coverage=[]
        for start,end,code in groups:
            start,end=int(start),int(end)
            coverage.extend(range(start,end+1))
            expected='\n'.join(lines[start-1:end])
            if code.replace('\r\n','\n')!=expected:
                errors.append(f'Grouped code mismatch: {source.name}:{start}-{end}')
        if coverage!=list(range(1,len(lines)+1)):
            errors.append(f'Grouped coverage/order: {source.name}')
        if len(groups)!=entry.get('groups'):
            errors.append(f'Group count mismatch: {source.name}: {len(groups)} vs {entry.get("groups")}')
        rtl_group_count+=len(groups)
        rtl_grouped_lines+=len(coverage)
    else:
        rows=re.findall(r'^\| \[(\d+)\]\(<([^>]+)>\) \| <code>(.*?)</code> \| (.*?) \|$',doc,re.M)
        if [int(x[0]) for x in rows]!=list(range(1,len(lines)+1)):
            errors.append(f'LUT coverage/order: {source.name}')
        for n,target,code,explanation in rows:
            original=html.unescape(code)
            expected=lines[int(n)-1] or '\xa0'
            if original!=expected: errors.append(f'LUT code mismatch: {source.name}:{n}')
            if not explanation.strip(): errors.append(f'Empty LUT explanation: {source.name}:{n}')
            expected_link=os.path.relpath(source,(OUT/entry['document']).parent).replace(os.sep,'/')+'#L'+n
            if unquote(target)!=expected_link: errors.append(f'LUT line link mismatch: {source.name}:{n}')
        total+=len(rows)

def markdown_anchors(path):
    # Match GitHub heading anchors while ignoring fenced source excerpts.
    body=re.sub(r'```.*?```','',path.read_text(encoding='utf-8'),flags=re.S)
    counts={}
    anchors=set()
    for heading in re.findall(r'^#{1,6}\s+(.+?)\s*#*$',body,re.M):
        heading=re.sub(r'\[([^\]]+)\]\([^)]*\)',r'\1',heading)
        heading=re.sub(r'<[^>]+>','',html.unescape(heading)).lower()
        slug=re.sub(r'[^\w\- ]','',heading).replace(' ','-')
        ordinal=counts.get(slug,0)
        counts[slug]=ordinal+1
        anchors.add(slug if ordinal==0 else f'{slug}-{ordinal}')
    return anchors

links=0
for path in [ROOT/'README.md',ROOT/'Verilog Source code'/'README.md',
             ROOT/'tests'/'README.md',ROOT/'tests'/'model_demo'/'README.md',
             ROOT/'tests'/'language_demo'/'README.md',ROOT/'tools'/'docs'/'README.md',
             *OUT.parent.rglob('*.md')]:
    text=path.read_text(encoding='utf-8')
    if text.count('```')%2: errors.append(f'Unclosed fence: {path.name}')
    for target in re.findall(r'\]\((<[^>]*>|[^)]+)\)',text):
        target=target.strip('<>')
        if target.startswith(('http','mailto:','data:','codex:')): continue
        target,_,fragment=target.partition('#')
        target=unquote(target)
        target=re.sub(r':\d+$','',target)
        p=(Path(target) if re.match(r'^[A-Za-z]:/',target) else path.parent/target) if target else path
        if not p.exists(): errors.append(f'Broken link: {path.name}: {target}')
        elif fragment and p.suffix.lower()=='.md' and unquote(fragment) not in markdown_anchors(p):
            errors.append(f'Broken heading anchor: {path.relative_to(ROOT)}: {target}#{fragment}')
        links+=1
if main_diagrams!=29: errors.append(f'Expected 29 main RTL diagrams, found {main_diagrams}')

# Keep render evidence tied to the current Mermaid text, not an old snapshot.
render_path=OUT/'diagram_validation.json'
rendered=0
if render_path.exists():
    render=json.loads(render_path.read_text(encoding='utf-8'))
    expected={}
    diagram_paths=[ROOT/'README.md',*OUT.parent.rglob('*.md')]
    for path in diagram_paths:
        for ordinal,graph in enumerate(re.findall(r'```mermaid\r?\n(.*?)\r?\n```',path.read_text(encoding='utf-8'),re.S)):
            key=(path.relative_to(ROOT).as_posix(),ordinal)
            expected[key]=hashlib.sha256(graph.replace('\r\n','\n').encode('utf-8')).hexdigest()
    evidence={(item['file'],item['ordinal']):item for item in render['diagrams']}
    if evidence.keys()!=expected.keys():
        errors.append('Mermaid render coverage mismatch')
    for key,sha in expected.items():
        item=evidence.get(key,{})
        if item.get('status')!='rendered' or item.get('source_sha256')!=sha:
            errors.append(f'Missing or stale Mermaid render: {key[0]}:{key[1]}')
        else:
            rendered+=1
else:
    errors.append('Missing Mermaid render evidence')

result={'snapshot_date':manifest['snapshot_date'],'source_files':len(manifest['files']),'main_rtl_diagrams':main_diagrams,'detail_diagrams':detail_diagrams,
        'rtl_logic_groups':rtl_group_count,'rtl_source_lines_grouped':rtl_grouped_lines,
        'lut_entries_explained':total,'links_checked':links,'mermaid_diagrams_rendered':rendered,'errors':errors,
        'scope':'Documentation coverage, source excerpts, line counts, headers, hashes, local links and Mermaid render evidence. Validator only; RTL regression and Quartus synthesis evidence are recorded separately in docs/reviews/design_review.md.'}
(OUT/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
print(json.dumps(result,ensure_ascii=False))
raise SystemExit(bool(errors))
