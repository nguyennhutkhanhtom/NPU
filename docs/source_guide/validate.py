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
    doc=(OUT/entry['document']).read_text(encoding='utf-8')
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

links=0
for path in OUT.rglob('*.md'):
    text=path.read_text(encoding='utf-8')
    if text.count('```')%2: errors.append(f'Unclosed fence: {path.name}')
    for target in re.findall(r'\]\((<[^>]*>|[^)]+)\)',text):
        target=target.strip('<>')
        if target.startswith(('http','#')): continue
        target=unquote(target.split('#',1)[0])
        target=re.sub(r':\d+$','',target)
        p=Path(target) if re.match(r'^[A-Za-z]:/',target) else path.parent/target
        if not p.exists(): errors.append(f'Broken link: {path.name}: {target}')
        links+=1
if main_diagrams!=29: errors.append(f'Expected 29 main RTL diagrams, found {main_diagrams}')
result={'source_files':len(manifest['files']),'main_rtl_diagrams':main_diagrams,'detail_diagrams':detail_diagrams,
        'rtl_logic_groups':rtl_group_count,'rtl_source_lines_grouped':rtl_grouped_lines,
        'lut_entries_explained':total,'links_checked':links,'errors':errors,
        'scope':'Documentation coverage, source fidelity, hashes and local links. No RTL changes or simulation rerun.'}
(OUT/'validation.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
raise SystemExit(bool(errors))
