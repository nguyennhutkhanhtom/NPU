#!/usr/bin/env python3
"""
Generate the square lookup table used by the RMSNorm hardware block.

Target fixed-point design
-------------------------
External datapath:
    16-bit signed Q4.12

Square-ROM input:
    Top 10 bits of the Q4.12 input: x[15:6]
    => signed Q4.6
    => range [-8.0, 7.984375]
    => 1024 LUT entries

Square-ROM output:
    x_lut^2
    The Q4.6 input has 6 fractional bits, therefore its exact square has
    12 fractional bits.

    The largest representable magnitude is x = -8.0:
        (-8.0)^2 = 64.0
        raw = 64 * 2^12 = 262144 = 2^18

    Therefore 19 unsigned bits are sufficient.
    We describe this explicitly as:
        19-bit unsigned, 12 fractional bits
        real_value = raw / 2^12

ROM address ordering
--------------------
The RTL flips the sign bit of the signed 10-bit Q4.6 input:

    addr = {~x_lut[9], x_lut[8:0]}

Therefore the ROM file must be ordered as:

    ROM[0]    -> -8.000000
    ROM[1]    -> -7.984375
    ...
    ROM[512]  ->  0.000000
    ...
    ROM[1023] ->  7.984375
"""

import argparse
import os


def generate_norm_square_rom(
    input_width: int = 10,
    input_int_bits: int = 4,
    output_file: str = "data/normContent.mif",
) -> None:
    if input_width <= 1:
        raise ValueError("input_width must be greater than 1")
    if not (1 <= input_int_bits <= input_width):
        raise ValueError("input_int_bits must be in [1, input_width]")

    input_frac_bits = input_width - input_int_bits
    square_frac_bits = 2 * input_frac_bits

    # For an N-bit signed two's-complement value, the most-negative raw
    # value is -2^(N-1). Squaring it requires bit position 2*(N-1),
    # hence 2*N-1 unsigned bits in total.
    square_width = 2 * input_width - 1

    num_entries = 1 << input_width
    min_signed_raw = -(1 << (input_width - 1))
    max_signed_raw = (1 << (input_width - 1)) - 1

    scale = 1 << input_frac_bits
    min_x = min_signed_raw / scale
    max_x = max_signed_raw / scale

    output_dir = os.path.dirname(output_file)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)

    print("==========================================")
    print("Generating RMSNorm square ROM")
    print("==========================================")
    print(f"Input width       : {input_width} bits")
    print(f"Input format      : signed Q{input_int_bits}.{input_frac_bits}")
    print(f"ROM entries       : {num_entries}")
    print(f"Input range       : {min_x:.9f} .. {max_x:.9f}")
    print(f"Input step        : {1/scale:.9f}")
    print(f"Square width      : {square_width} bits unsigned")
    print(f"Square frac bits  : {square_frac_bits}")
    print(f"Square scale      : 2^{square_frac_bits} = {1 << square_frac_bits}")
    print(f"Output file       : {output_file}")
    print()

    checkpoints = {
        0,
        1,
        (1 << (input_width - 1)) - (1 << input_frac_bits),  # -1.0
        (1 << (input_width - 1)),                            #  0.0
        (1 << (input_width - 1)) + (1 << input_frac_bits),  # +1.0
        num_entries - 2,
        num_entries - 1,
    }

    with open(output_file, "w", newline="\n") as f:
        for addr in range(num_entries):
            # Because the RTL sign-bit flip maps addresses monotonically:
            # addr=0 -> min signed raw, addr=512 -> 0, ...
            signed_raw = min_signed_raw + addr
            x = signed_raw / scale

            # Exact fixed-point square:
            #
            # x = signed_raw / 2^F
            # x^2 = signed_raw^2 / 2^(2F)
            #
            # Therefore the stored raw value is simply signed_raw^2.
            square_raw = signed_raw * signed_raw

            if square_raw >= (1 << square_width):
                raise RuntimeError(
                    f"Square value {square_raw} does not fit in "
                    f"{square_width} bits"
                )

            bits = f"{square_raw:0{square_width}b}"
            f.write(bits + "\n")

            if addr in checkpoints:
                square_real = square_raw / (1 << square_frac_bits)
                print(
                    f"addr={addr:4d}  "
                    f"x={x:10.6f}  "
                    f"x^2={square_real:11.7f}  "
                    f"raw={square_raw:6d}  "
                    f"bin={bits}"
                )

    print()
    print(f"Successfully generated {num_entries} entries.")
    print()
    print("RTL checkpoint:")
    print("  Q4.12 input -> use x[15:6] as the Q4.6 square-ROM input.")
    print("  ROM[512] must be zero because address 512 represents x = 0.")
    print("  ROM[448] and ROM[576] must both represent 1.0.")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate the square LUT for the Q4.12 RMSNorm unit."
    )
    parser.add_argument("--input-width", type=int, default=10)
    parser.add_argument("--input-int-bits", type=int, default=4)
    parser.add_argument("-o", "--output", default=None)
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    output_file = args.output
    if output_file is None:
        output_file = os.path.join(
            project_root, "data", "normContent.mif"
        )

    generate_norm_square_rom(
        input_width=args.input_width,
        input_int_bits=args.input_int_bits,
        output_file=output_file,
    )


if __name__ == "__main__":
    main()
