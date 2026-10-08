"""Linux Xcelium/Genus runner. Run compute stages only in a Slurm allocation.

python3 tools/server/run_flow.py --check-inputs
python3 tools/server/run_flow.py --stage all --tag my_run --lib /lab/cells.lib
python3 tools/server/run_flow.py --stage application --tag app_run --fixture /path/to/fixtures
Reports are written to reports/TAG; compiled databases stay in build/TAG.
Application stage uses supplied fixtures and is functional verification only.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tcl_string(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('$', '\\$').replace('[', '\\[').replace('\n', '\\n') + '"'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage', choices=('test', 'application', 'legacy', 'syn', 'all'), default='test')
    p.add_argument('--tag', default=datetime.now(timezone.utc).strftime('run_%Y%m%d_%H%M%S'))
    p.add_argument('--lib', type=Path, action='append', default=[])
    p.add_argument('--syn-ram-blackbox', action='store_true',
                   help='Genus only: preserve sram_word_tile as SRAM black boxes')
    p.add_argument('--syn-top', choices=('llm_soc', 'llm_parameter_ram', 'llm_bank_ram'), default='llm_soc',
                   help='Use a RAM wrapper top for a lightweight mapped synthesis check')
    p.add_argument('--sdc', type=Path, default=ROOT / 'tools/server/asic.sdc')
    p.add_argument('--only', nargs='+', help='Select test tops; does not claim full regression PASS')
    p.add_argument('--fixture', type=Path, default=ROOT / 'tests/full_rtl/build')
    p.add_argument('--check-inputs', action='store_true')
    a = p.parse_args()
    if (a.syn_ram_blackbox or a.syn_top != 'llm_soc') and a.stage not in ('syn', 'all'):
        p.error('--syn-ram-blackbox/--syn-top require syn/all; Xcelium always uses functional RAM')
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,64}', a.tag):
        p.error('tag must contain only letters, digits, underscore or hyphen')
    manifest_path = ROOT / 'bundle_manifest.json'
    rtl = ROOT / ('rtl' if (ROOT / 'rtl').is_dir() else 'Verilog Source code')
    config_path = ROOT / 'tools/server/flow.json'
    config = json.loads(config_path.read_text())
    tests = tuple((t['file'], t['top'], t['marker']) for t in config['tests'])
    if a.only and (a.stage not in ('test', 'all') or not set(a.only) <= {t[1] for t in tests}):
        p.error('--only must select known tops in test/all stage')
    inputs = list(rtl.glob('*.sv')) + list(rtl.glob('*.svh')) + list(rtl.glob('*.mem'))
    inputs += list((ROOT / 'tests/full_rtl').glob('*.sv'))
    inputs += [Path(__file__).resolve(), config_path, ROOT / 'tools/server/genus.tcl', a.sdc.resolve()]
    if a.stage == 'legacy':
        inputs += [ROOT / 'tests/tb_all.sv', ROOT / 'tests/reference.py']
    for file in inputs:
        if not file.is_file():
            p.error('Missing input: ' + str(file))
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {
        'files': {str(f.resolve()).replace('\\', '/'): digest(f) for f in inputs}}
    for name, expected in manifest['files'].items():
        file = ROOT / name
        if not file.is_file() or digest(file) != expected:
            raise RuntimeError('Missing or changed bundle input: ' + name)
    for name, _, _ in tests:
        if not (ROOT / 'tests/full_rtl' / name).is_file():
            raise RuntimeError('Missing testbench: ' + name)
    if a.stage == 'application':
        for name in ('config.svh', 'parameter.mem', 'prompt.mem', 'expected.mem', 'reference.json'):
            if not (a.fixture / name).is_file():
                p.error('Missing application input: ' + name)
        reference = json.loads((a.fixture / 'reference.json').read_text())
        for name in ('config.svh', 'parameter.mem', 'prompt.mem', 'expected.mem'):
            if digest(a.fixture / name) != reference['input_files'][name]:
                p.error('Application fixture does not match reference: ' + name)
        for file in rtl.iterdir():
            if file.suffix in ('.sv', '.svh', '.mem') and file.name not in config['exclude']:
                if digest(file) != reference['rtl_sources'].get(file.name):
                    p.error('Application reference has different RTL: ' + file.name)
    if a.check_inputs:
        print('FLOW_INPUTS_VERIFIED files=' + str(len(manifest['files'])))
        return
    import sys
    import socket
    if sys.platform != 'linux' or not os.environ.get('SLURM_JOB_ID'):
        p.error('Compute stages require an existing Slurm allocation; do not run on the login node.')
    nodes = subprocess.check_output(['scontrol', 'show', 'hostnames', os.environ['SLURM_JOB_NODELIST']], universal_newlines=True).split()
    if socket.gethostname().split('.')[0] not in nodes:
        p.error('Current host is outside the Slurm allocation')
    if not os.environ.get('DISPLAY') or not shutil.which('xdpyinfo'):
        p.error('Authenticated X11 is required; launch with srun --x11')
    if subprocess.run(['xdpyinfo'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5).returncode:
        p.error('Compute X11 connection failed; do not omit --x11')
    for tool in (['xrun'] if a.stage in ('test', 'application', 'legacy', 'all') else []) + (['genus'] if a.stage in ('syn', 'all') else []):
        if not shutil.which(tool):
            p.error('Missing tool on PATH: ' + tool + '; load the lab module in your allocated shell')
    if a.stage in ('syn', 'all'):
        if not a.lib:
            p.error('Supply --lib for each lab Liberty library required for mapped ASIC synthesis')
        for lib in a.lib:
            if not lib.is_file():
                p.error('Missing library: ' + str(lib))
        if not a.sdc.is_file():
            p.error('Missing SDC: ' + str(a.sdc))
    if a.stage == 'application':
        fixture = a.fixture
        for name in ('config.svh', 'parameter.mem', 'prompt.mem', 'expected.mem', 'reference.json'):
            if not (fixture / name).is_file():
                p.error('Missing application input: ' + name)
    report = ROOT / 'reports' / a.tag
    build = ROOT / 'build' / a.tag
    if report.exists() or build.exists():
        p.error('Tag already exists; use a fresh tag to preserve reports/databases')
    report.mkdir(parents=True)
    build.mkdir(parents=True)
    results = {'status': 'RUNNING', 'stage': a.stage, 'slurm_job_id': os.environ['SLURM_JOB_ID'],
               'started_utc': datetime.now(timezone.utc).isoformat(), 'node': socket.gethostname(),
               'display': os.environ['DISPLAY'], 'x11_connection': 'VERIFIED',
               'python_version': sys.version,
               'bundle_manifest_sha256': digest(manifest_path) if manifest_path.exists() else None,
               'inputs': manifest['files'], 'commands': [], 'tests': {},
               'scope': 'New server evidence; separate from local FPGA gates and ASIC physical signoff'}
    libs = [lib.resolve() for lib in a.lib]
    results['synthesis_top'] = a.syn_top
    results['synthesis_ram_blackbox'] = a.syn_ram_blackbox
    results['libraries'] = {str(lib): digest(lib) for lib in libs}
    results['sdc_sha256'] = digest(a.sdc)
    if a.stage == 'application':
        results['fixtures'] = {name: digest(a.fixture / name)
                               for name in ('config.svh', 'parameter.mem', 'prompt.mem', 'expected.mem', 'reference.json')}

    def save():
        temporary = report / 'results.tmp'
        temporary.write_text(json.dumps(results, indent=2) + '\n')
        temporary.replace(report / 'results.json')

    def run(command, log, cwd=ROOT):
        results['commands'].append(command)
        save()
        print('START ' + log.name, flush=True)
        with log.open('w') as stream:
            status = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT).returncode
        if status:
            raise RuntimeError(f'Tool exit={status}; inspect {log}')

    packages = [rtl / name for name in config['packages']]
    sources = packages + sorted(f for f in rtl.glob('*.sv') if f not in packages and f.name not in config['exclude'])
    save()
    try:
        if a.stage in ('test', 'application', 'legacy', 'all'):
            run(['xrun', '-version'], report / 'xrun.version.log')
        selected = tests if a.stage in ('test', 'all') else (
            (('application_tb.sv', 'tb_full_rtl_application', 'FULL_RTL_APPLICATION_PASS'),)
            if a.stage == 'application' else ())
        if a.only:
            selected = tuple(t for t in selected if t[1] in a.only)
        if a.stage == 'legacy':
            selected = tuple(('tb_all.sv', 'tb_' + name, name.upper() + '_PASS')
                             for name in config['legacy'])
        for filename, top, marker in selected:
            working = build / top
            working.mkdir()
            include = rtl
            if a.stage == 'legacy':
                vectors = working / 'tests/sim'
                run([sys.executable, str(ROOT / 'tests/reference.py'), '--rtl', str(rtl),
                     '--block', 'All', '--output', str(vectors)], report / (top + '.reference.log'), working)
            if a.stage == 'application':
                isolated = working / 'tests/full_rtl/build'
                isolated.mkdir(parents=True)
                include = isolated
                for name in ('parameter.mem', 'prompt.mem', 'expected.mem', 'config.svh'):
                    shutil.copyfile(a.fixture / name, isolated / name)
            listing = report / (top + '_sources.f')
            listing.write_text('\n'.join('"' + str(f) + '"' for f in
                               sources + [ROOT / ('tests' if a.stage == 'legacy' else 'tests/full_rtl') / filename]) + '\n')
            log = report / (top + '.console.log')
            tool_log = report / (top + '.log')
            run(['xrun', '-64bit', '-timescale', '1ns/1ps', '-access', '+rwc', '-top', top,
                 '-xmlibdirname', str(working / 'xcelium.d'), '+incdir+' + str(rtl),
                 '+incdir+' + str(include), '+SIGMOID_LUT=' + str(rtl / 'sigmoid_257.mem'),
                 '-f', str(listing), '-l', str(tool_log)], log, working)
            text = log.read_text(errors='replace') + (tool_log.read_text(errors='replace') if tool_log.exists() else '')
            if not re.search(r'\b' + marker + r'\b', text) or re.search(r'\*[EFW],|\*\*\s+(?:Error|Fatal|Warning)|\$fatal', text):
                raise RuntimeError('Missing completion marker or simulator diagnostic: ' + top)
            results['tests'][top] = {'marker': marker, 'console_sha256': digest(log)}
            print('VERIFIED ' + marker, flush=True)
            if a.stage == 'application':
                results['application_scope'] = 'Functional fixture token matching only; no FPGA hardware gate or ASIC signoff claim'
                shutil.copyfile(isolated / 'rtl_tokens.txt', report / 'rtl_tokens.txt')
        if a.stage in ('syn', 'all'):
            run(['genus', '-version'], report / 'genus.version.log', build)
            setup = report / 'genus_setup.tcl'
            synth_sources = [f for f in sources if f.name != 'quartus_word_ram.sv']
            setup.write_text('set task_root ' + tcl_string(ROOT) + '\nset task_rtl ' + tcl_string(rtl) + '\nset task_report ' + tcl_string(report) +
                             '\nset task_libs [list ' + ' '.join(tcl_string(f) for f in libs) + ']' +
                             '\nset task_sdc ' + tcl_string(a.sdc.resolve()) +
                             '\nset task_top ' + tcl_string(a.syn_top) +
                             '\nset task_ram_blackbox ' + ('1' if a.syn_ram_blackbox else '0') +
                             '\nset task_sources [list ' + ' '.join(tcl_string(f) for f in synth_sources) + ']\n' +
                             'source ' + tcl_string(ROOT / 'tools/server/genus.tcl') + '\n')
            log = report / 'genus.console.log'
            run(['genus', '-no_gui', '-batch', '-files', str(setup)], log, build)
            synth_log = log.read_text(errors='replace')
            if 'GENUS_FLOW_COMPLETED' not in synth_log:
                raise RuntimeError('Missing Genus completion marker')
            if re.search(r'^\s*(?:Error\s*:|Fatal\s*:|GENUS_FLOW_FAILED:)', synth_log, re.MULTILINE):
                raise RuntimeError('Genus error diagnostic; inspect genus.console.log')
            for name in (a.syn_top + '.v', a.syn_top + '.sdc', 'area.rpt', 'timing.rpt',
                         'generic_area.rpt', 'check_design.rpt', 'check_design_mapped.rpt'):
                if not (report / name).is_file() or not (report / name).stat().st_size:
                    raise RuntimeError('Missing synthesis output: ' + name)
            if re.search(r'\baltsyncram\b', (report / (a.syn_top + '.v')).read_text(errors='replace')):
                raise RuntimeError('FPGA RAM macro appeared in the ASIC netlist')
            results['synthesis'] = 'GENUS_FLOW_COMPLETED; review check_design/area/timing reports'
            results['synthesis_review'] = 'REQUIRED: unresolved references, mapping, warnings and 10 ns timing; inferred RAM has no SRAM binding'
            if a.syn_ram_blackbox:
                # Genus 21.1 represents empty HDL leaves as logic abstracts,
                # not mapped insts with is_black_box. Check their emitted bodies.
                netlist = (report / (a.syn_top + '.v')).read_text(errors='replace')
                netlist = re.sub(r'/\*.*?\*/|//[^\n]*', '', netlist, flags=re.DOTALL)
                leaves = re.findall(r'\bmodule\s+(sram_word_tile\w*)\s*\([^;]*\);(.*?)\bendmodule',
                                    netlist, re.DOTALL)
                if not leaves:
                    raise RuntimeError('No RAM black-box modules in mapped netlist')
                counts = {}
                for name, body in leaves:
                    statements = [s.strip() for s in body.split(';') if s.strip()]
                    if not statements or any(not re.match(r'^(input|output|inout|wire)\b', s) for s in statements):
                        raise RuntimeError('RAM leaf contains mapped logic/storage: ' + name)
                    if not all(re.search(r'\b' + port + r'\b', body) for port in
                               ('clk', 'rd_en', 'wr_en', 'rd_addr', 'wr_addr', 'wr_data', 'rd_data')):
                        raise RuntimeError('RAM black-box interface incomplete: ' + name)
                    counts[name] = len(re.findall(r'\b' + re.escape(name) + r'\s+\S+\s*\(', netlist))
                    if not counts[name]:
                        raise RuntimeError('RAM black-box module has no instances: ' + name)
                results['ram_blackboxes'] = counts
                (report / 'ram_blackboxes.rpt').write_text(json.dumps(counts, indent=2) + '\n')
                print('RAM_BLACKBOX_CHECK_PASS instances=' + str(sum(counts.values())), flush=True)
                results['synthesis_review'] = 'REQUIRED: RAM black boxes have no SRAM area/timing arcs; wrapper/logic reports are not complete ASIC PPA'
        for name, expected in manifest['files'].items():
            if digest(ROOT / name) != expected:
                raise RuntimeError('Input changed during run: ' + name)
        for lib in libs:
            if digest(lib) != results['libraries'][str(lib)]:
                raise RuntimeError('Library changed during synthesis: ' + str(lib))
        if digest(a.sdc) != results['sdc_sha256']:
            raise RuntimeError('SDC changed during execution')
        for name, expected in results.get('fixtures', {}).items():
            if digest(a.fixture / name) != expected:
                raise RuntimeError('Application fixture changed during execution: ' + name)
        if a.stage in ('test', 'legacy', 'all'):
            results['regression'] = 'SELECTED_GROUPS_PASS' if a.only else 'FULL_SERVER_REGRESSION_PASS'
        results['status'] = 'COMPLETED'
    except BaseException as error:
        results['status'] = 'FAIL'
        results['failure'] = str(error)
        raise
    finally:
        results['finished_utc'] = datetime.now(timezone.utc).isoformat()
        results['report_hashes'] = {f.name: digest(f) for f in report.iterdir() if f.is_file() and f.name != 'results.json'}
        save()
    print('FLOW_COMPLETED reports=' + str(report))


if __name__ == '__main__':
    main()
