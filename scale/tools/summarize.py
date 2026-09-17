"""Verify baseline/trace and summarize available logs. Never calls unrun tests PASS."""
from pathlib import Path
import hashlib,json,difflib,re
ROOT=Path(__file__).resolve().parents[2]
SCALE=ROOT/'scale'
SIM=SCALE/'sim'
RTL=ROOT/'Verilog Source code'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
baseline=json.loads((SCALE/'baseline/manifest.json').read_text(encoding='utf-8-sig'))
for item in baseline:
    p=SCALE/'baseline'/Path(item['Path']).name
    assert sha(p)==item['Hash'].lower(),f'Preserved baseline changed: {p}'
for name in ['ctrl_unit.sv','hazard_detect.sv','matmul_wrap.sv']:
    assert sha(RTL/name)==sha(SCALE/'baseline'/name),f'Control flow changed: {name}'
a,b=SIM/'trace-original.txt',SIM/'trace-param.txt'
assert a.exists() and b.exists() and sha(a)==sha(b),'Default trace mismatch'
tests={
  'alu-scaled.log':'SCALED_ALU_LEGACY_PASS comparisons=524288',
  'tb_scaled_storage.log':'SCALED_STORAGE_PASS',
  'tb_scaled_ddr.log':'SCALED_DDR_PASS',
  'top-default.log':'TOP_SMOKE_PASS pc_width=9 word_width=512',
  'top-scaled.log':'TOP_SMOKE_PASS pc_width=6 word_width=256',
}
results={}
for name,marker in tests.items():
    content=(SIM/name).read_text(encoding='utf-8',errors='replace') if (SIM/name).exists() else ''
    results[name]={'status':'PASS' if marker in content else 'NOT_COMPLETED',
                   'scope':'reset/HALT smoke only' if name.startswith('top-') else 'legacy behavior / widths',
                   'marker':marker if marker in content else None}
    if not name.startswith('top-'): assert marker in content,f'Missing required result: {name}'
diff=[]
for item in baseline:
    name=Path(item['Path']).name
    old=(SCALE/'baseline'/name).read_text(encoding='utf-8',errors='replace')
    new=(RTL/name).read_text(encoding='utf-8',errors='replace')
    diff.extend(difflib.unified_diff((old.rstrip('\n')+'\n').splitlines(True),(new.rstrip('\n')+'\n').splitlines(True),
                 fromfile='a/Verilog Source code/'+name,tofile='b/Verilog Source code/'+name))
new_wrapper=(RTL/'matmulfree_scaled.sv').read_text(encoding='utf-8')
diff.extend(difflib.unified_diff([],new_wrapper.splitlines(True),fromfile='/dev/null',tofile='b/Verilog Source code/matmulfree_scaled.sv'))
(SCALE/'parameterization.diff').write_text(''.join(diff),encoding='utf-8')
summary={'scope':'Parameterization only; known functional bugs intentionally retained',
         'baseline_files_verified':len(baseline),
         'default_trace':{'cycles':len(a.read_text().splitlines()),'sha256':sha(a),'identical':True},
         'tests':results,
         'rtl_sha256':{p.name:sha(p) for p in sorted(RTL.iterdir()) if p.suffix in ('.sv','.v')}}
(SCALE/'verification.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in summary.items() if k!='rtl_sha256'},indent=2))
