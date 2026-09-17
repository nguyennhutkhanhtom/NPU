"""Synthetic bit-pattern fixtures for width/regression tests, NOT LLM golden data."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'sim'
root.mkdir(exist_ok=True)
for bits in (8,16):
    suffix='_8' if bits==8 else ''
    with (root/f'sigContent{suffix}.mif').open('w') as f:
        for i in range(1<<bits): f.write(f'{i:0{bits}b}\n')
    with (root/f'exp_content{suffix}.mif').open('w') as f:
        for i in range(512): f.write(f'{i% (1<<bits):0{bits//4}x}\n')
    with (root/('mem_init_8.mem' if bits==8 else 'mem_init.mem')).open('w') as f:
        for i in range(16384 if bits==8 else 524288):
            # Distinguishable lanes/addresses expose width truncation/reordering.
            word=sum(((i+j)% (1<<bits)) << (j*bits) for j in range(32))
            f.write(f'{word:0{bits*8}x}\n')
for depth,name in [(512,'instruction.mem'),(64,'instruction_64.mem')]:
    (root/name).write_text(('1111111111111\n')*depth)
print('Generated synthetic width-test fixtures.')
