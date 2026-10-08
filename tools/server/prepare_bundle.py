"""Prepare current run inputs only, excluding documentation and past evidence."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--application', action='store_true', help='Include already prepared application fixtures')
    a = p.parse_args()
    output = a.output.resolve()
    build = (ROOT / 'tests/full_rtl/build').resolve()
    if build not in output.parents or output.exists():
        p.error('Output must be a new directory under tests/full_rtl/build')
    files = {}
    for file in (ROOT / 'Verilog Source code').iterdir():
        if file.is_file() and file.suffix in ('.sv', '.v', '.svh', '.mem') and file.name != 'quartus_word_ram.sv':
            files['rtl/' + file.name] = file
    for file in (ROOT / 'tests/full_rtl').iterdir():
        if file.is_file() and file.suffix == '.sv':
            files['tests/full_rtl/' + file.name] = file
    for name in ('run_flow.py', 'run.sh', 'flow.json', 'genus.tcl', 'asic.sdc', 'README.md'):
        files['tools/server/' + name] = ROOT / 'tools/server' / name
    for name in ('reference.py', 'tb_all.sv'):
        files['tests/' + name] = ROOT / 'tests' / name
    # Generated stimulus/expected values are test INPUTS, not old PASS evidence.
    for name in (('config.svh', 'parameter.mem', 'prompt.mem', 'expected.mem', 'reference.json') if a.application else ()):
        files['tests/full_rtl/build/' + name] = build / name
    for file in files.values():
        if not file.is_file() or file.is_symlink():
            p.error('Missing/unsupported input: ' + str(file))
    output.mkdir(parents=True)
    hashes = {}
    for name, file in sorted(files.items()):
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(file, target)
        hashes[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    manifest = {'created_utc': datetime.now(timezone.utc).isoformat(),
                'scope': 'Portable sources and test inputs; no credentials, vendor model or past PASS evidence',
                'files': hashes}
    (output / 'bundle_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('BUNDLE_READY files=' + str(len(files) + 1) + ' output=' + str(output))


if __name__ == '__main__':
    main()
