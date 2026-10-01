"""One-time, checked conversion of llm_soc's operator control to one-hot.

The graph and numeric payloads stay unchanged. Direct state bits avoid wide
binary decoders on each SIMD payload enable; debug retains the old op index.
"""
from pathlib import Path
import re

path = Path(__file__).resolve().parents[2] / 'Verilog Source code/llm_soc.sv'
text = path.read_text(encoding='utf-8')
if 'localparam int OP_COUNT' in text:
    print('ONE_HOT_CONTROL: already converted')
    raise SystemExit(0)
pattern = re.compile(r'typedef enum logic \[6:0\] \{(.*?)\} op_t;', re.S)
found = pattern.search(text)
if not found:
    raise ValueError('Expected original 7-bit operator enum')
names = [name.strip() for name in found[1].split(',')]
if len(names) != len(set(names)) or any(not re.fullmatch('[A-Z][A-Z0-9_]*', name) for name in names):
    raise ValueError('Unexpected operator enum')
declarations = f'localparam int OP_COUNT = {len(names)};\n'
declarations += '\n'.join(f'    localparam int {name}_IDX = {index};' for index, name in enumerate(names))
declarations += '\n    typedef enum logic [OP_COUNT - 1:0] {\n'
declarations += ',\n'.join(f"        {name} = OP_COUNT'(1) << {name}_IDX" for name in names)
declarations += '\n    } op_t;'
text = text[:found.start()] + declarations + text[found.end():]
for name in names:
    text = re.sub(r'\bop == ' + name + r'\b', f'op[{name}_IDX]', text)
if text.count('case (op)') != 2:
    raise ValueError('Expected exactly two operator-controlled datapaths')
# Convert labels only inside the two operator case statements. Their inner
# cases use lowercase signals and numeric labels, so names remain unambiguous.
lines = text.splitlines()
in_operator = False
for index, line in enumerate(lines):
    if 'case (op)' in line:
        lines[index] = line.replace('case (op)', 'case (1\'b1)')
        in_operator = True
        continue
    if in_operator:
        label = re.match(r'^(\s*)((?:[A-Z][A-Z0-9_]*\s*,\s*)*[A-Z][A-Z0-9_]*)\s*:(.*)$', line)
        if label and all(name.strip() in names for name in label[2].split(',')):
            bits = ', '.join(f'op[{name.strip()}_IDX]' for name in label[2].split(','))
            lines[index] = f'{label[1]}{bits} :{label[3]}'
text = '\n'.join(lines) + '\n'
helper = '''    function automatic logic [6:0] op_index(input op_t value);
        op_index = 0;
        for (int index = 0; index < OP_COUNT; index = index + 1)
            op_index = op_index | (7'(index) & {7{value[index]}});
    endfunction

'''
text = text.replace('    // Registered host transactions.', helper + '    // Registered host transactions.', 1)
text = text.replace("instr_debug <= {1'b0, graph, op};", "instr_debug <= {1'b0, graph, op_index(op)};")
if 'case (op)' in text or re.search(r'\bop == ', text):
    raise ValueError('An operator decoder was left unconverted')
path.write_text(text, encoding='utf-8', newline='\n')
print(f'ONE_HOT_CONTROL_PASS states={len(names)}; debug index preserved')
