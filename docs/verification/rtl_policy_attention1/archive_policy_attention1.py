from pathlib import Path
from hashlib import sha256
import json, re, shutil
root = Path(__file__).resolve().parents[3]
rtl = root / 'Verilog Source code'
initial = json.loads((root/'tests/full_rtl/build/attention1_modelsim_start.json').read_text(encoding='utf-8-sig'))
hashes = {p.name:sha256(p.read_bytes()).hexdigest() for p in rtl.iterdir() if p.suffix in ('.sv','.v','.svh','.mem')}
assert hashes == initial['rtl_sources']
procedural = {'matmulfree.sv': {314:8,339:8}, 'norm.sv': {213:2,234:2,241:2,245:2},
              'rowwise_op.sv': {74:2,111:2,120:2,122:2,131:2,142:2}, 'pipelined_word_ram.sv': {88:4}}
geometry = {'logic_mul.sv': {21,31}}
loops, functions, arithmetic, vendor = [], [], [], []
for p in sorted(rtl.iterdir()):
    if p.suffix not in ('.sv','.v','.svh'): continue
    code = re.sub(r'/\*.*?\*/', lambda m:'\n'*m[0].count('\n'), p.read_text(encoding='utf-8-sig'), flags=re.S)
    code = re.sub(r'//[^\n]*','', code)
    assert not re.search(r'\b(task|while|repeat|forever)\b', code), p.name
    assert not re.search(r'`ifn?def\s+(QUARTUS_)?SYNTHESIS\b', code), p.name
    for n, line in enumerate(code.splitlines(), 1):
        if re.search(r'\bfor\s*\(', line):
            kind = 'generate structural replication'
            item = {'file':p.name,'line':n,'source':line.strip()}
            if n in procedural.get(p.name, {}):
                kind = 'small static procedural hardware'; item['bound'] = procedural[p.name][n]
            elif n in geometry.get(p.name, set()): kind = 'constant elaboration geometry; ROWS bound'
            item['classification'] = kind; loops.append(item)
        if re.search(r'\bfunction\s+automatic', line):
            functions.append({'file':p.name,'line':n,'source':line.strip(),
                'classification':'constant elaboration geometry' if p.name=='logic_mul.sv' else 'small pure combinational helper'})
        stripped = line.replace('::*','').replace('@(*)','')
        stripped = re.sub(r'\(\*.*?\*\)', '', stripped)
        if re.search(r'\*|/', stripped):
            arithmetic.append({'file':p.name,'line':n,'source':stripped.strip(),
                'review':'Constant geometry/index factors only; no runtime multiplication/division.'})
        if re.search(r'\b(altsyncram|altmult\w*|lpm_\w+|altera_\w+)\b', stripped):
            vendor.append({'file':p.name,'line':n,'source':stripped.strip()})
assert len(functions)==15
assert sum(x['classification']=='small static procedural hardware' for x in loops)==13
assert all(x['file']=='quartus_word_ram.sv' for x in vendor)
out = root/'docs/verification/rtl_policy_attention1'; out.mkdir(exist_ok=False)
shutil.copy2(Path(__file__), out/'archive_policy_attention1.py')
result = {'status':'SOURCE_REVIEW_PASS','scope':'Manual source review with lexical inventory of the exact attention1 snapshot; not a SystemVerilog parser, functional proof, synthesis, timing, ASIC signoff or application gate.',
 'rtl_sources':hashes,'rules_sha256':sha256((root/'AGENTS.md').read_bytes()).hexdigest(),
 'review':{'runtime_arithmetic':'Bit-product compressor trees, shift/subtract divider and radicand/trial-subtract integer square root; registers, muxes, comparisons, bitwise, add/subtract, shifts. All listed multiplication/division symbols reviewed as elaboration-only.',
 'functions':'13 runtime pure combinational helpers, two elaboration-only geometry functions. No FSM, handshake, memory access, pipeline or sequential register ownership in functions.',
 'ownership':'llm_soc requests/FSM updates inline; SIMD lanes and reduction pipeline registers generated. Small procedural loops bound two lanes, four mux members or eight legacy metadata slots. No variable/unbounded loops or synthesizable task.',
 'technology':'Only quartus_word_ram instantiates altsyncram; memory adapters document latency/collision/reset. dont_merge hints confined to memory adapters. Physical QSF settings are EDA backend binding.'},
 'loops':loops,'functions':functions,'arithmetic_symbols':arithmetic,'vendor_symbols':vendor,
 'command':'python tests/full_rtl/build/archive_policy_attention1.py',
 'inventory_helper_sha256':sha256(Path(__file__).read_bytes()).hexdigest()}
(out/'results.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
print(f'SOURCE_REVIEW_PASS assets={len(hashes)} loops={len(loops)} functions={len(functions)} arithmetic_statements={len(arithmetic)}')
