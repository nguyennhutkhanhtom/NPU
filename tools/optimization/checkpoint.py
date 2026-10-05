"""Archive task-specific checkpoints and report non-comment RTL change counts."""
from pathlib import Path
from hashlib import sha256
import argparse
import difflib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / 'Verilog Source code'
BASE = ROOT / 'docs/verification/optimization_baseline/rtl'

def code_lines(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return [code.strip() for line in text.splitlines()
            if (code := line.split('//', 1)[0]).strip()]

def changes():
    names = sorted({p.name for d in (BASE, RTL) for p in d.iterdir()
                    if p.suffix in {'.sv', '.v', '.svh'}})
    denominator = added = deleted = 0
    files = []
    for name in names:
        before = code_lines((BASE/name).read_text(encoding='utf-8-sig')) if (BASE/name).exists() else []
        after = code_lines((RTL/name).read_text(encoding='utf-8-sig')) if (RTL/name).exists() else []
        denominator += len(before)
        a = d = 0
        for op, i, j, k, l in difflib.SequenceMatcher(a=before, b=after, autojunk=False).get_opcodes():
            if op in ('replace', 'delete'): d += j-i
            if op in ('replace', 'insert'): a += l-k
        added += a
        deleted += d
        if a or d: files.append({'file': name, 'added': a, 'deleted': d})
    return {'baseline_code_lines': denominator, 'added_code_lines': added,
            'deleted_code_lines': deleted, 'percentage': 100*(added+deleted)/denominator,
            'files': files, 'scope': 'Task-start RTL tree, excluding comments, blank lines, tests and reports'}

def archive(tag):
    out = ROOT/'tests/full_rtl/evidence'/tag
    out.mkdir(exist_ok=False)
    unit = json.loads((ROOT/'tests/full_rtl/unit_results.json').read_text(encoding='utf-8-sig'))
    for sub, source in [('rtl', RTL), ('tests', ROOT/'tests/full_rtl')]:
        (out/sub).mkdir()
        for p in source.iterdir():
            if p.is_file() and (sub == 'tests' or p.suffix in {'.sv','.v','.svh','.mem'}):
                shutil.copy2(p, out/sub/p.name)
    for item in unit.get('evidence', {}).values():
        for path in [item['log'], item.get('design_units', {}).get('file')]:
            if path:
                shutil.copy2(ROOT/path, out/Path(path).name)
    # Preserve compiler diagnostics and the exact file list even on a failure.
    for name in ('compile.log', 'compile.console', 'sources.f', 'vlib.log'):
        source = ROOT/'tests/full_rtl/build'/name
        if source.is_file():
            shutil.copy2(source, out/name)
    # Failed/interrupted runners may not serialize their per-top evidence map.
    # Exclude stale logs from earlier attempts using this compilation timestamp.
    compile_log = ROOT/'tests/full_rtl/build/compile.log'
    if compile_log.is_file():
        for source in (ROOT/'tests/full_rtl/build').glob('tb_*.log'):
            if source.stat().st_mtime >= compile_log.stat().st_mtime:
                shutil.copy2(source, out/source.name)
    shutil.copy2(ROOT/'tests/full_rtl/unit_results.json', out/'results.json')
    (out/'rtl_changes.json').write_text(json.dumps(changes(), indent=2)+'\n')
    hashes = {str(p.relative_to(out)).replace('\\','/'): sha256(p.read_bytes()).hexdigest()
              for p in out.rglob('*') if p.is_file()}
    (out/'archive_hashes.json').write_text(json.dumps(hashes, indent=2)+'\n')
    print('CHECKPOINT_ARCHIVED:', out)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive')
    args = parser.parse_args()
    if args.archive: archive(args.archive)
    else: print(json.dumps(changes(), indent=2))
