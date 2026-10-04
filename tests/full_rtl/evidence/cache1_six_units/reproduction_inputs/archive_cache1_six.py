from pathlib import Path
from hashlib import sha256
import json,shutil,re,sys
root=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(root/'tests/full_rtl'))
from memory_model import verify_model,verify_design_units
build=root/'tests/full_rtl/build'
initial=json.loads((build/'cache1_modelsim_start.json').read_text(encoding='utf-8-sig'))
current={p.name:sha256(p.read_bytes()).hexdigest() for p in (root/'Verilog Source code').iterdir() if p.suffix in ('.sv','.v','.svh','.mem')}
assert current==initial['rtl_sources']
tests={p.name:sha256(p.read_bytes()).hexdigest() for p in (root/'tests/full_rtl').iterdir() if p.name.startswith('tb_') and p.suffix=='.sv' or p.name=='run_units.ps1'}
assert tests==initial['test_sources']
model=verify_model(build/'questa25_model/manifest.json',root/'docs/verification/timing/fullrtl100_attention1/manifest.json',Path('C:/altera_lite/25.1std/questa_fse/win64'))
out=root/'tests/full_rtl/evidence/cache1_six_units';out.mkdir(exist_ok=False)
evidence={};markers={}
for top in ('tb_quartus_memory','tb_llm_math','tb_llm_ram','tb_llm_protocol','tb_llm_selection','tb_llm_operators'):
 log=build/(top+'.log');text=log.read_text()
 assert 'Errors: 0, Warnings: 0' in text and not re.search(r'^# \*\* (Fatal|Error|Warning)|UI-Msg \(Error\)',text,re.M)
 matches=[line for line in text.splitlines() if '_PASS' in line];assert len(matches)==1
 markers[top]=matches[0];shutil.copy2(log,out/log.name)
 du=build/('cache1_'+top+'_design_units.json')
 verify_design_units(du,model,top in ('tb_quartus_memory','tb_llm_protocol','tb_llm_selection'))
 shutil.copy2(du,out/du.name)
 evidence[top]={'log':(out/log.name).relative_to(root).as_posix(),'sha256':sha256(log.read_bytes()).hexdigest(),
  'design_units':{'file':(out/du.name).relative_to(root).as_posix(),'sha256':sha256(du.read_bytes()).hexdigest()}}
for name in ('compile.log','cache1_modelsim_start.json'):shutil.copy2(build/name,out/name)
assert 'Errors: 0, Warnings: 0' in (out/'compile.log').read_text()
shutil.copy2(build/'questa25_model/manifest.json',out/'memory_model_manifest.json')
result={'status':'SIX_GROUPS_PASS_GRAPH_RUNNING','scope':'Current 34 assets: KV payload samples continuously in each generated lane, binary vector operand held independently; all test inputs/numeric expectations unchanged; not a trained application',
 'rtl_sources':current,'test_sources':tests,'tests':markers,'evidence':evidence,
 'simulator':'QuestaAlteraStarter2025.2','model':model,
 'runner_sources':{'tests/full_rtl/memory_model.py':sha256((root/'tests/full_rtl/memory_model.py').read_bytes()).hexdigest()},
 'compile_sha256':sha256((out/'compile.log').read_bytes()).hexdigest(),
 'initial_snapshot_sha256':sha256((out/'cache1_modelsim_start.json').read_bytes()).hexdigest(),
 'model_manifest_sha256':sha256((out/'memory_model_manifest.json').read_bytes()).hexdigest(),
 'graph':'RUNNING: same source/tests, actual RAM25.1 binding; no PASS claimed',
 'runtime_warnings':0,'fixture_changes':'No test source or expected value change for continuous cache operand capture. Existing reset/fixture contracts retained, no suppressed errors.'}
inputs=out/'reproduction_inputs';inputs.mkdir()
for name in tests:shutil.copy2(root/'tests/full_rtl'/name,inputs/name)
shutil.copy2(root/'tests/full_rtl/memory_model.py',inputs/'memory_model.py')
shutil.copy2(Path(__file__),inputs/'archive_cache1_six.py')
result['reproduction_inputs']={p.name:sha256(p.read_bytes()).hexdigest() for p in inputs.iterdir()}
result['command']='./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_attention1/manifest.json -WorkLibraryName cache1_questa_work -EvidenceTag cache1'
result['reset_release_contract']='Async assert/two rising edges to release; operator fixture waits before all deposits/seeding. Exact 2/3/9 arithmetic stage checks and independent values retained.'
(out/'results.json').write_text(json.dumps(result,indent=2)+'\n')
print('CACHE1_SIX_UNIT_ARCHIVE_PASS: 34 RTL, 8 test inputs, 6 binding reports, zero compile/runtime warnings, graph RUNNING')

