from pathlib import Path
import sys, re, json, base64, zlib, urllib.parse, xml.etree.ElementTree as E
from collections import Counter
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/docs'))
import build_hierarchy as h
def model(d):
    m=d.find('mxGraphModel')
    return m if m is not None else E.fromstring(urllib.parse.unquote(zlib.decompress(base64.b64decode(d.text),-15).decode()))
for p in [ROOT/'reference/Ethos_U85_mini.drawio',ROOT/'rtl_hierarchy.drawio',ROOT/'docs/diagrams/rtl_hierarchy_portable.drawio']:
    print('\nFILE',p.relative_to(ROOT))
    for d in E.parse(p).getroot().findall('diagram'):
        cs=model(d).findall('.//mxCell');print('PAGE',d.get('name'),len(cs))
        if 'reference' in str(p):
            for sty,n in Counter(c.get('style','') for c in cs if c.get('vertex')=='1' or c.get('edge')=='1').most_common(12):
                ex=next(c for c in cs if c.get('style','')==sty)
                print(n,ex.get('id'),repr(ex.get('value','')[:80]),sty)
mods=[]
for name,m in h.MODULES.items():
    b=m['body']; hdr=b[:b.index(';')+1]
    mods.append({'module':name,'file':m['file'],'header':hdr,'instances':m['templates'],
      'states':re.findall(r'typedef\s+enum.*?\{(.*?)\}',b,re.S),
      'registers':re.findall(r'^\s*(?:logic|reg|wire)\s+([^;]+);',b,re.M),
      'clock_reset':sorted(set(re.findall(r'@\((.*?)\)',b))),
      'assignments':re.findall(r'assign\s+([^;]+);',b),
      'source_sha256':h.sha256((h.RTL/m['file']).read_bytes()).hexdigest()})
inventory=[]
for p in [ROOT/'README.md',*sorted((ROOT/'docs').rglob('*.md'))]:
    if any(x in p.parts for x in ['node_modules','timing','optimization_baseline','npu100_b1_baseline']):continue
    for i,g in enumerate(re.findall(r'```mermaid\s*\n(.*?)\n```',p.read_text(encoding='utf-8'),re.S),1):
        inventory.append({'file':p.relative_to(ROOT).as_posix(),'index':i,'graph':g})
out=ROOT/'scratchpad/diagram_inventory.json';out.write_text(json.dumps({'modules':mods,'diagrams':inventory},indent=2),encoding='utf-8')
print('MODULES',len(mods),'MERMAID',len(inventory))
print('SAVED',out)
