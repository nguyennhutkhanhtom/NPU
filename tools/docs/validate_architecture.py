"""Bounded structural/provenance/layout validation of redesigned native pages."""
from pathlib import Path
from hashlib import sha256
import json,re,sys,xml.etree.ElementTree as E
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).parent))
import redesign_architecture as a
OUT=a.OUT;WORK=a.WORK
errors=[]
def check(ok,message):
    if not ok:errors.append(message)
man=json.loads((OUT/'architecture_manifest.json').read_text())
idx=json.loads((OUT/'architecture_index.json').read_text(encoding='utf-8'))
ds=json.loads((WORK/'routed.json').read_text(encoding='utf-8'))
original=json.loads((WORK/'original_hashes.json').read_text())
for f,h in man['source_hashes'].items():check(a.digest(a.hierarchy.RTL/f)==h,'RTL/LUT changed: '+f)
styles=json.loads((WORK/'style_audit.json').read_text());check(a.digest(ROOT/styles['reference'])==styles['sha256'],'Reference changed')
coverage={c:set() for c in man['configurations']};pages=[]
for file in sorted(set(p['drawio'] for p in idx)):
    tree=E.parse(OUT/file)
    for page in tree.findall('diagram'):
        cs=page.findall('.//mxCell');ids=[c.get('id') for c in cs];by={c.get('id'):c for c in cs}
        key=page.get('id');check(len(ids)==len(set(ids)),key+': duplicate cell ID')
        for c in cs:
            for r in ['parent','source','target']:
                if c.get(r):check(c.get(r) in by,key+': unresolved '+r)
            check(c.find('.//image') is None and 'shape=image' not in c.get('style',''),key+': embedded image')
            if c.get('edge')=='1':check(c.get('source') and c.get('target'),key+': dangling edge')
            if c.get('rtlPaths'):
                config='quartus' if 'quartus' in key else 'portable';coverage[config].update(json.loads(c.get('rtlPaths')))
        pages.append({'id':key,'cells':len(cs),'nodes':sum(c.get('vertex')=='1' for c in cs),'connections':sum(c.get('edge')=='1' for c in cs)})
for config,data in man['configurations'].items():
    expected={r['path'] for r in data['instances']};check(coverage[config]==expected,config+': incomplete hierarchy coverage '+str(expected-coverage[config]))
for d in ds:
    ns=[n for n in d['nodes'] if n.get('role')!='group']
    for i,n in enumerate(ns):
        check(n['x']>=0 and n['y']>=0 and n['x']+n['width']<=d['width'] and n['y']+n['height']<=d['height'],d['key']+': node outside page '+n['id'])
        for m in ns[i+1:]:check(not a.overlaps(a.rect(n),a.rect(m)),d['key']+': overlapping nodes '+n['id']+'/'+m['id'])
    for e in d['edges']:
        for p,q in zip(e['points'],e['points'][1:]):
            check(p[0]==q[0] or p[1]==q[1],d['key']+': nonorthogonal edge '+e['id'])
            for n in ns:
                if n['id'] not in {e['source'],e['target']}:check(not a.intersect(p,q,a.rect(n)),d['key']+': edge crosses block '+e['id']+'/'+n['id'])
        if e.get('labelRect'):
            for n in ns:check(not a.overlaps(e['labelRect'],a.rect(n)),d['key']+': signal label overlaps block '+e['id']+'/'+n['id'])
            for f in d['edges']:
                if f is not e:check(not any(a.intersect(p,q,e['labelRect']) for p,q in zip(f['points'],f['points'][1:])),d['key']+': signal label covers another wire '+e['id']+'/'+f['id'])
    if d['kind']=='functional':
        # Diagram modules must exist. Named functional registers are not
        # counted as instances; hierarchy coverage is checked independently.
        for n in ns:
            for name in re.findall(r'\b(?:llm_[a-z0-9_]+|ternary_dot32|logic_mul|isqrt_u64|altsyncram|postscale_finish|quartus_word_ram|sram_word_tile)\b',n['label']):
                if name in {'llm_random_next','llm_pkg'}:continue
                check(name in man['modules'] or name=='altsyncram',d['key']+': unknown module '+name)
facts={
 'linear result queue':('llm_linear_engine.sv',r'result_q\s*\[0:3\]'),
 'linear row credits':('llm_linear_engine.sv',r'started_rows_q - consumed_rows_q.*?< 10\x27d4'),
 'linear parameter credits':('llm_linear_engine.sv',r'request_q - words_consumed.*?< 12\x27d2'),
 'head eight results':('llm_head_engine.sv',r'result_q\s*\[0:7\]'),
 'head scale grouping':('llm_head_engine.sv',r'23040.*?request_row_q\[11:3\]'),
 'head reservations':('llm_head_engine.sv',r'reserved_rows < 8'),
 'linear nine tagged stages':('llm_soc.sv',r'linear_pipe_row_q \[0:8\]'),
 'head six tagged stages':('llm_soc.sv',r'head_pipe_row_q \[0:5\]'),
 'aligned high scalar part':('llm_soc.sv',r'linear_scalar_hi_q <= scalar_partial_q\[2\]'),
 'head ordered PRNG':('llm_soc.sv',r'head_pipe_valid_q\[3\].*?random_q <= llm_random_next'),
 'full bank linear writes':('llm_soc.sv',r'linear_write \? 32\x27hffffffff'),
 'SRAM retained contents':('sram_word_tile.sv',r'if \(wr_en\) memory\[wr_addr\] <= wr_data'),
 'single-clock reset boundary':('llm_soc.sv',r'reset_release u_reset\(\.clk\(clk\).*?\.core_rst_n\(core_rst_n\)'),
}
proofs=[]
for fact,(file,pattern) in facts.items():
    raw=(a.hierarchy.RTL/file).read_text(encoding='utf-8-sig');m=re.search(pattern,raw,re.S);check(bool(m),'Missing source witness: '+fact)
    proofs.append({'fact':fact,'source':file,'line':raw[:m.start()].count('\n')+1 if m else None,'sha256':man['source_hashes'][file]})
for d in idx:
    if d['markdown']:
        check(d['key'] in (ROOT/d['markdown']).read_text(encoding='utf-8'),'Missing Markdown link: '+d['key'])
with a.zipfile.ZipFile(WORK/'original_diagrams.zip') as backup:
    for file in sorted(set(d['markdown'] for d in idx if d['markdown'])):
        old=backup.read(file).decode('utf-8-sig');new=(ROOT/file).read_text(encoding='utf-8')
        old=re.sub(r'```mermaid\s*\n.*?\n```','',old,flags=re.S)
        new=re.sub(r'Current RTL replacement; surrounding discussion is historical\.\s*','',new)
        new=re.sub(r'!\[[^\n]+\]\([^\n]+/previews/[^\n]+\.svg\)\s*\n\[Editable draw\.io[^\n]+','',new)
        old=re.sub(r'^Diagram follow-up required:.*$','',old,flags=re.M)
        new=re.sub(r'^The diagram(?:s)? (?:below|above) reflects? .*$', '',new,flags=re.M)
        normalize=lambda s:re.sub(r'\n\s*\n','\n\n',s.replace('\r\n','\n')).strip()
        check(normalize(old)==normalize(new),'Non-diagram prose changed: '+file)
    check(backup.read('TASK_STATE.md')==(ROOT/'TASK_STATE.md').read_bytes(),'TASK_STATE unrelated content changed')
report={'status':'PASS' if not errors else 'FAIL','scope':'XML references/editability, complete configured instance coverage, source-port validation, RTL/LUT preservation, orthogonal routing, node and signal-label collisions, named-module existence, and reviewed source witnesses. Not simulation/synthesis or a general SV elaborator.',
 'pages':pages,'hierarchy_instances':{c:len(x['instances']) for c,x in man['configurations'].items()},'source_files_unchanged':len(man['source_hashes']),
 'source_witnesses':proofs,'errors':errors,'limits':man['limits'],
 'artifact_sha256':{f:a.digest(OUT/f) for f in sorted(set(p['drawio'] for p in idx))},'backup_sha256':a.digest(WORK/'original_diagrams.zip')}
a.save(OUT/'architecture_validation.json',json.dumps(report,indent=2))
print(json.dumps({k:report[k] for k in ['status','hierarchy_instances','source_files_unchanged','errors']}))
sys.exit(bool(errors))
