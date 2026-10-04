from pathlib import Path
from hashlib import sha256
from datetime import datetime, timezone
import json,re,shutil
root=Path(__file__).resolve().parents[3]; b=root/'tests/full_rtl/build/portable_cache1'
u=json.loads((root/'tests/full_rtl/evidence/cache1_all_units/results.json').read_text())
rtl={p.name:sha256(p.read_bytes()).hexdigest() for p in (root/'Verilog Source code').iterdir() if p.suffix in ('.sv','.v','.svh','.mem')}
assert u['status']=='PASS' and rtl==u['rtl_sources']
text=(b/'elaborate.log').read_text(encoding='utf-8',errors='replace')
assert 'Errors: 0, Warnings: 0' in text and not re.search(r'\*\* (Warning|Error|Fatal)',text)
du=json.loads((b/'design_units.json').read_text())
units=[v['UNIT'] for v in du['DESIGN_UNITS'] if v['UNIT']['TYPE']=='MODULE']
names=sorted({v['PRIMARY'] for v in units})
assert 'llm_soc' in names and 'sram_word_tile' in names
assert not any(re.match(r'(alt|altera|cyclone|arria|stratix|lpm_)',n,re.I) for n in names),names
assert not re.search(r'# Loading .*?(altera|altsyncram|cyclone)',text,re.I)
compile_path=root/'tests/full_rtl/evidence/cache1_all_units/compile.log'
assert sha256(compile_path.read_bytes()).hexdigest()==u['compile_sha256']
out=root/'docs/verification/portable_elaboration_cache1';out.mkdir(exist_ok=False)
files={n:b/n for n in ('elaborate.log','elaborate.console','commands.json','design_units.json')}
files.update({'compile.log':compile_path,'sources.f':root/'tests/full_rtl/build/sources.f',
 'run_portable_cache1.ps1':root/'tests/full_rtl/build/run_portable_cache1.ps1','archive_portable_cache1.py':Path(__file__)})
for n,p in files.items():shutil.copy2(p,out/n)
m={'status':'ELABORATION_PASS','completed_utc':datetime.now(timezone.utc).isoformat(),'top':'llm_soc',
 'parameter':{'USE_QUARTUS_MEMORY':0},'simulator':'Questa Altera Starter2025.2','vendor_memory_library_loaded':False,
 'module_names':names,'module_design_units':len(units),'errors':0,'warnings':0,'rtl_sources':rtl,'source_hashes_verified':True,
 'compiled_unit_evidence':'tests/full_rtl/evidence/cache1_all_units/results.json',
 'archives':{n:{'sha256':sha256((out/n).read_bytes()).hexdigest()} for n in files},
 'commands':['./tests/full_rtl/build/run_portable_cache1.ps1','python tests/full_rtl/build/archive_portable_cache1.py'],
 'scope':'Exact-current cache1 full-top elaboration, reusing the verified all-seven compiled library; no vendor memory -L argument/binding. run0, no weights or inference. Behavioral SRAM verification backend; not selected foundry SRAM, ASIC synthesis/STA/signoff or application gate.'}
(out/'results.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8',newline='\n')
print('PORTABLE_CACHE1_ARCHIVE_PASS:',len(units),'module units;',len(names),'names;0errors0warnings;no vendor bindings')
