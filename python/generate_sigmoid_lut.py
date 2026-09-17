#!/usr/bin/env python3
"""
Generate sigmoid ROM contents for the Sig_ROM hardware.

Target design:
- Datapath input: signed Q4.12, 16 bits
- Sig_ROM input: 10 bits, obtained from datapath_input[15:6]
  => signed Q4.6
- Sig_ROM output: 16-bit Q4.12
- ROM depth: 2^10 = 1024 entries

Sig_ROM remaps signed two's-complement x into monotonically increasing
ROM addresses by flipping the sign bit:
    addr = {~x[9], x[8:0]}

Therefore:
    ROM[0]    -> x = -8.0
    ROM[512]  -> x =  0.0
    ROM[1023] -> x =  7.984375
"""

import argparse
import math
import os


def sigmoid(x: float) -> float:
    """Numerically stable sigmoid."""
    if x >= 0.0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    z = math.exp(x)
    return z / (1.0 + z)


def quantize_positive(value: float, total_bits: int, frac_bits: int) -> int:
    """Quantize a non-negative real number to fixed point."""
    scale = 1 << frac_bits
    q = int(round(value * scale))
    return max(0, min(q, (1 << total_bits) - 1))


def generate_sigmoid_rom(
    input_width: int = 10,
    input_int_bits: int = 4,
    output_width: int = 16,
    output_int_bits: int = 4,
    output_file: str = "data/sigmoid/sigContent.mif",
) -> None:
    """
    Generate ROM data matching Sig_ROM.

    Q-format convention:
      signed QI.F, where I includes the sign bit.

    Current design:
      Sig_ROM input  = Q4.6  (10 bits)
      Sig_ROM output = Q4.12 (16 bits)
    """
    if input_width <= 0 or output_width <= 0:
        raise ValueError("Bit widths must be positive.")
    if not (1 <= input_int_bits <= input_width):
        raise ValueError("input_int_bits must be in [1, input_width].")
    if not (1 <= output_int_bits <= output_width):
        raise ValueError("output_int_bits must be in [1, output_width].")

    input_frac_bits = input_width - input_int_bits
    output_frac_bits = output_width - output_int_bits

    num_entries = 1 << input_width
    input_scale = 1 << input_frac_bits

    min_signed_raw = -(1 << (input_width - 1))
    max_signed_raw = (1 << (input_width - 1)) - 1

    min_x = min_signed_raw / input_scale
    max_x = max_signed_raw / input_scale
    step = 1.0 / input_scale

    output_dir = os.path.dirname(output_file)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    print("==========================================")
    print("Generating Sigmoid ROM")
    print("==========================================")
    print(f"Input width       : {input_width} bits")
    print(f"Input format      : signed Q{input_int_bits}.{input_frac_bits}")
    print(f"ROM entries       : {num_entries}")
    print(f"Input range       : {min_x:.9f} .. {max_x:.9f}")
    print(f"Input step        : {step:.9f}")
    print(f"Output width      : {output_width} bits")
    print(f"Output format     : Q{output_int_bits}.{output_frac_bits}")
    print(f"Output scale      : 2^{output_frac_bits} = {1 << output_frac_bits}")
    print(f"Output file       : {output_file}")
    print()

    zero_addr = 1 << (input_width - 1)

    with open(output_file, "w", newline="\n") as f:
        for addr in range(num_entries):
            # Because Sig_ROM flips the sign bit:
            # addr 0       -> minimum signed input
            # addr 512     -> x = 0 for input_width=10
            # addr 1023    -> maximum positive input
            signed_raw = min_signed_raw + addr
            x = signed_raw / input_scale

            sig = sigmoid(x)
            q = quantize_positive(sig, output_width, output_frac_bits)

            f.write(f"{q:0{output_width}b}\n")

            if (
                addr < 5
                or addr in {zero_addr - 1, zero_addr, zero_addr + 1}
                or addr >= num_entries - 5
            ):
                print(
                    f"addr={addr:4d}  "
                    f"x={x:10.6f}  "
                    f"sigmoid={sig:.9f}  "
                    f"raw={q:5d}  "
                    f"bin={q:0{output_width}b}"
                )

    zero_q = quantize_positive(sigmoid(0.0), output_width, output_frac_bits)

    print()
    print(f"Successfully generated {num_entries} entries.")
    print(f"Check: ROM[{zero_addr}] = sigmoid(0) = 0.5")
    print(f"       raw = {zero_q}")
    print(f"       bin = {zero_q:0{output_width}b}")
    print()
    print("Hardware connection for a 16-bit Q4.12 datapath:")
    print("    .x(a[i][15:6])")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate sigmoid ROM contents matching Sig_ROM."
    )
    parser.add_argument("--input-width", type=int, default=10)
    parser.add_argument("--input-int-bits", type=int, default=4)
    parser.add_argument("--output-width", type=int, default=16)
    parser.add_argument("--output-int-bits", type=int, default=4)
    parser.add_argument("-o", "--output", default=None)

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    output_file = args.output
    if output_file is None:
        output_file = os.path.join(
            project_root, "data", "sigmoid", "sigContent.mif"
        )

    generate_sigmoid_rom(
        input_width=args.input_width,
        input_int_bits=args.input_int_bits,
        output_width=args.output_width,
        output_int_bits=args.output_int_bits,
        output_file=output_file,
    )


if __name__ == "__main__":
    main()
