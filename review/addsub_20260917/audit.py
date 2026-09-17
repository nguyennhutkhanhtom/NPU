"""Record exact source scope, stale-report evidence and static index proofs."""
from pathlib import Path
import difflib
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
RTL = ROOT / 'Verilog Source code'
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
before = json.loads((HERE / 'rtl-before.json').read_text(encoding='utf-8-sig'))
before = {Path(row['Path']).name: row['Hash'].lower() for row in before}
files = sorted(p for p in RTL.iterdir() if p.suffix in ('.v', '.sv'))
after = {p.name: digest(p) for p in files}
changed = [name for name in after if before[name] != after[name]]
assert sorted(changed) == ['addsub.sv', 'rowwise_op.sv'], changed
baseline_matches = [p.name for p in files if before[p.name] == digest(ROOT/'scale/baseline'/p.name)]
assert len(baseline_matches) == 22

verification = json.loads((HERE/'verification.json').read_text(encoding='utf-8-sig'))
for name, expected in verification['sources'].items():
    assert digest(ROOT/name) == expected, f'Verification is stale: {name}'

historical = json.loads((ROOT/'functional/verification.json').read_text(encoding='utf-8-sig'))
stale = []
for name, expected in historical['rtl_sha256'].items():
    path = RTL / Path(name).name
    if not path.exists() or digest(path) != expected:
        stale.append(name)

ternary = (RTL/'ternary_mul.sv').read_text()
assert 'tmatrix_data [262143:0]' in ternary
assert 'tmatrix_data[i * 512 + j] = tmatrix[i][j * 2 +: 2]' in ternary
indices = [i*512+j for i in range(1024) for j in range(256)]
valid = {n for n in indices if n < 262144}
proof = {
    'rtl_files_reviewed': len(files),
    'pre_edit_files_matching_baseline': len(baseline_matches),
    'rtl_changed_this_turn': changed,
    'rtl_sha256_after': after,
    'historical_functional_report_mismatches_or_missing': stale,
    'ternary_index_proof': {
        'out_of_bounds_assignments': sum(n >= 262144 for n in indices),
        'undriven_in_range': 262144-len(valid),
        'maximum_index': max(indices),
    },
    'exp_invalid_indices_of_65536': sum((a ^ 32768) >= 512 for a in range(65536)),
}
(HERE/'audit.json').write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8')
diff = []
for name in changed:
    old = (HERE/'before'/name).read_text().splitlines(keepends=True)
    new = (RTL/name).read_text().splitlines(keepends=True)
    for line in difflib.unified_diff(old,new,fromfile='a/Verilog Source code/'+name,tofile='b/Verilog Source code/'+name):
        diff.append(line if line.endswith('\n') else line+'\n\\ No newline at end of file\n')
(HERE/'addsub.patch').write_text(''.join(diff),encoding='utf-8')
print(json.dumps(proof,ensure_ascii=False,indent=2))
