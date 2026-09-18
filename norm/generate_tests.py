"""Independent integer oracle for the specified 32-lane Q4.12/Q4.6 flow."""
from pathlib import Path
import hashlib
import json
import math
import random
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "norm" / "sim"
OUT.mkdir(exist_ok=True)
sys.path.insert(0, str(ROOT / "python"))
from generate_norm_lut import generate_norm_square_rom


def model(values):
    assert len(values) == 32
    # Python // deliberately floors negative inputs, just like x[15:6].
    square_sum = sum((x // 64) ** 2 for x in values)
    rms = math.isqrt(square_sum * 128)
    raw = [0 if rms == 0 else (-1 if x < 0 else 1) * (abs(x) * 4096 // rms)
           for x in values]
    overflow = any(x < -32768 or x > 32767 for x in raw)
    return [min(32767, max(-32768, x)) for x in raw], overflow, rms, square_sum


def packed(values):
    return f"{sum((x & 65535) << (16*i) for i, x in enumerate(values)):0128x}"


def write_words(name, words):
    (OUT / name).write_text("\n".join(packed(v) for v in words) + "\n")


def main():
    # Generate to the test directory; verify the delivered asset without replacing it.
    generate_norm_square_rom(output_file=str(OUT / "normContent.mif"))
    generated = (OUT / "normContent.mif").read_text().splitlines()
    delivered = (ROOT / "data" / "normContent.mif").read_text().splitlines()
    assert generated == delivered
    assert len(delivered) == 1024
    assert all(len(bits) == 19 and int(bits, 2) == (i-512)**2
               for i, bits in enumerate(delivered))

    rng = random.Random(0x4_12_4_6)
    edges = [-32768, -32767, -4096, -129, -128, -127, -65, -64, -63,
             -1, 0, 1, 31, 63, 64, 65, 127, 128, 4096, 32766, 32767]
    vectors = [[x]*32 for x in edges]
    vectors += [[x if i == lane else 0 for i in range(32)]
                for lane in range(32) for x in edges]
    vectors += [[q*64 + i*2 + 1 for i in range(32)] for q in range(-512, 512)]
    vectors += [[127 if i == lane else 63 for i in range(32)] for lane in range(32)]
    for _ in range(2048):
        limit = rng.choice([2, 64, 128, 4096, 32768])
        vectors.append([rng.randrange(-limit, limit) for _ in range(32)])
    results = [model(v) for v in vectors]
    write_words("unit-input.hex", vectors)
    write_words("unit-expected.hex", [r[0] for r in results])
    (OUT / "unit-flags.hex").write_text("".join(f"{int(r[1]):x}\n" for r in results))
    (OUT / "unit-rms.hex").write_text("".join(f"{r[2]:04x}\n" for r in results))
    (OUT / "unit-sum.hex").write_text("".join(f"{r[3]:06x}\n" for r in results))

    # Real-core program: high source/destination, in-place, consecutive NORM,
    # ADD producer/consumer, independent differently-scaled words, and HALT.
    regs = [[[0]*32 for _ in range(16)] for _ in range(8)]
    for word in range(16):
        regs[7][word] = [rng.randrange(-32768, 32768) for _ in range(32)]
    regs[7][0] = [127]+[63]*31  # saturation; retained across instruction words
    regs[7][1] = [0]*32
    regs[7][2] = [-32768]*32
    regs[7][3] = [63]*32       # quantized-zero, despite nonzero full inputs
    regs[7][4] = [64]*32
    regs[7][5] = [4096]*32
    initial = [list(word) for bank in regs for word in bank]
    program = [(7, 6, 0, 7), (7, 6, 0, 6), (7, 1, 0, 6),
               (1, 2, 1, 1), (7, 3, 0, 2), (7, 7, 0, 3)]
    trace, flags, snapshots = [], [], []
    for op, dst, src_b, src_a in program:
        if op == 7:
            result = [model(w) for w in regs[src_a]]
            regs[dst] = [r[0] for r in result]
            trace.extend(regs[dst])
            flags.append(int(any(r[1] for r in result)))
            snapshots.extend([list(w) for bank in regs for w in bank])
        else:
            regs[dst] = [[((a+b+32768) % 65536)-32768 for a, b in zip(wa, wb)]
                         for wa, wb in zip(regs[src_a], regs[src_b])]
    write_words("core-initial.hex", initial)
    write_words("core-expected.hex", trace)
    write_words("core-final.hex", [word for bank in regs for word in bank])
    write_words("core-snapshots.hex", snapshots)
    (OUT / "core-flags.hex").write_text("".join(f"{x:x}\n" for x in flags))
    encoded = [(op << 9) | (dst << 6) | (b << 3) | a for op, dst, b, a in program]
    (OUT / "instruction.mem").write_text("".join(f"{i:013b}\n" for i in encoded+[8191]*(512-len(encoded))))
    (OUT / "fixtures.svh").write_text(f"localparam UNIT_CASES={len(vectors)};\n")
    # Existing combinational ALU tables are inactive in NORM tests.
    (OUT / "sigContent.mif").write_text("0000000000000000\n"*1024)
    (OUT / "exp_content.mif").write_text("0000\n"*512)
    metadata = {"unit_vectors": len(vectors), "unit_lane_comparisons": len(vectors)*32,
                "lut_entries": 1024, "norm_instructions": len(flags),
                "lut_sha256": hashlib.sha256((ROOT / "data/normContent.mif").read_bytes()).hexdigest()}
    (OUT / "fixtures.json").write_text(json.dumps(metadata, indent=2)+"\n")
    print(json.dumps(metadata))


if __name__ == "__main__":
    main()
