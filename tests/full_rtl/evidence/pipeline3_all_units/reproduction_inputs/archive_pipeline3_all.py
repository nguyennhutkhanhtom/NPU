from pathlib import Path
from hashlib import sha256
import json, shutil, re, sys
root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / 'tests/full_rtl'))
from memory_model import verify_model, verify_design_units
build = root / 'tests/full_rtl/build'
result = json.loads((root / 'tests/full_rtl/unit_results.json').read_text(encoding='utf-8-sig'))
initial = json.loads((build / 'pipeline3_modelsim_start.json').read_text(encoding='utf-8-sig'))
digest = lambda p: sha256(p.read_bytes()).hexdigest()
current = {p.name: digest(p) for p in (root / 'Verilog Source code').iterdir() if p.suffix in ('.sv', '.v', '.svh', '.mem')}
tests = {p.name: digest(p) for p in (root / 'tests/full_rtl').iterdir() if (p.name.startswith('tb_') and p.suffix == '.sv') or p.name == 'run_units.ps1'}
assert result['status'] == 'PASS' and len(result['tests']) == 7
assert current == initial['rtl_sources'] == result['rtl_sources']
assert tests == initial['test_sources'] == result['test_sources']
for name, expected in result['runner_sources'].items(): assert digest(root / name) == expected
model = verify_model(build / 'questa25_model/manifest.json', root / 'docs/verification/timing/fullrtl100_explicit2/manifest.json', Path('C:/altera_lite/25.1std/questa_fse/win64'))
out = root / 'tests/full_rtl/evidence/pipeline3_all_units'
assert not out.exists()
out.mkdir()
for top, evidence in result['evidence'].items():
    log = root / evidence['log']
    text = log.read_text()
    assert digest(log) == evidence['sha256'] and 'Errors: 0, Warnings: 0' in text
    assert result['tests'][top] in text and not re.search(r'^# \*\* (Fatal|Error|Warning)|UI-Msg \(Error\)', text, re.M)
    shutil.copy2(log, out / log.name)
    evidence['log'] = (out / log.name).relative_to(root).as_posix()
    du = root / evidence['design_units']['file']
    assert digest(du) == evidence['design_units']['sha256']
    verify_design_units(du, model, top in ('tb_quartus_memory', 'tb_llm_protocol', 'tb_llm_selection', 'tb_llm_graph'))
    shutil.copy2(du, out / du.name)
    evidence['design_units']['file'] = (out / du.name).relative_to(root).as_posix()
for name in ('compile.log', 'pipeline3_modelsim_start.json'): shutil.copy2(build / name, out / name)
assert 'Errors: 0, Warnings: 0' in (out / 'compile.log').read_text()
shutil.copy2(build / 'questa25_model/manifest.json', out / 'memory_model_manifest.json')
inputs = out / 'reproduction_inputs'
inputs.mkdir()
for name in tests: shutil.copy2(root / 'tests/full_rtl' / name, inputs / name)
shutil.copy2(root / 'tests/full_rtl/memory_model.py', inputs / 'memory_model.py')
shutil.copy2(Path(__file__), inputs / 'archive_pipeline3_all.py')
result.update(simulator='QuestaAlteraStarter2025.2', model=model, runtime_warnings=0,
    memory_model_manifest=(out / 'memory_model_manifest.json').relative_to(root).as_posix(),
    compile_sha256=digest(out / 'compile.log'), initial_snapshot_sha256=digest(out / 'pipeline3_modelsim_start.json'),
    model_manifest_sha256=digest(out / 'memory_model_manifest.json'),
    reproduction_inputs={p.name: digest(p) for p in inputs.iterdir()},
    command='./tests/full_rtl/run_units.ps1 -SimBin C:/altera_lite/25.1std/questa_fse/win64 -Questa -MemoryModelManifest tests/full_rtl/build/questa25_model/manifest.json -TimingManifest docs/verification/timing/fullrtl100_explicit2/manifest.json -WorkLibraryName pipeline3_questa_work -EvidenceTag pipeline3',
    timing_manifest_note='Historical timing manifest supplies the official RAM model provenance only; it is FAIL and does not approve an application.',
    scope='Exact-current 34 RTL assets and eight test inputs: all seven synthetic unit/operator/full-graph groups PASS. This is not pretrained language generation.')
(out / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
print('PIPELINE3_ALL_UNIT_ARCHIVE_PASS: 34 RTL assets, eight test inputs, seven groups/binding reports, zero compile/runtime warnings')
