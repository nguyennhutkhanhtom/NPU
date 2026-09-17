# Functional repair — current entry point

RTL is in `../Verilog Source code`. Read [CONTRACT.md](CONTRACT.md) for the numeric, memory-map and handshake decisions, and [FIX_REPORT.md](FIX_REPORT.md) for the review finding mapping. [verification.json](verification.json) records test results and hashes of the delivered RTL. [rtl.patch](rtl.patch) is the code-only diff against the clean pre-repair Git revision.

## Run from the project directory

```powershell
./functional/run.ps1                              # Complete 8-bit + 16-bit regression and report
./functional/run.ps1 -Group Alu,Norm -Widths 8     # Relevant tests during arithmetic edits
./functional/run.ps1 -Group Storage,Ddr            # Interface tests
./functional/run.ps1 -Group Core -Widths 8         # Executable 23-instruction program
./functional/run.ps1 -Group Guards                 # Expected rejection of invalid configurations
./functional/run.ps1 -RegenerateAssets             # Rebuild numeric assets, then full regression
```

ModelSim Intel FPGA Starter 2020.1 is the configured simulator. Override `-SimBin` and `-Python` when needed. All RTL, including `mem_burst.v`, is compiled in SystemVerilog mode. Run one script at a time; the runner locks its simulation library. Full transcripts stay in `sim/`; console output is limited to PASS markers and failure excerpts.

A partial run does not replace the complete verification report. The reporter rejects results predating its build manifest or changes to compiled RTL/testbench sources. Run the full command to produce a fresh complete report after code changes. Compile diagnostics 13314/2583 are ModelSim notices about unpacked-array port defaults and additional combinational checking; functional test transcripts must have no runtime errors.

## Supported profiles

| Property | Default core | Scaled wrapper |
|---|---:|---:|
| Top | matmulfree | matmulfree_scaled |
| Data / fractional bits | 16 / 12 | 8 / 4 |
| Packed word | 512 bits | 256 bits |
| Register depth / pointer | 1024 / 10 bits | 128 / 7 bits |
| RAM depth / pointer | 524288 / 19 bits | 32768 / 15 bits |
| Instruction depth / PC | 512 / 9 bits | 64 / 6 bits |
| EXP and SIG entries | 65536 each | 256 each |
| Ternary weights per word | 256 | 128 |
| Matrix frame words | 1024 | 2048 |
| Ternary accumulator | 26 bits | 18 bits |
| Logical main RAM | 32 MiB | 1 MiB |

The scaled RAM grew from the earlier 16384-word parameter-only profile because vector banks and all eight matrices now occupy separate address ranges. Minimum legal depths are 9216 words (16-bit) and 17408 words (8-bit); the storage tests exercise those non-power-of-two depths.

Default init paths select the numeric assets for the chosen data width. Override them for another workload; `INIT_FILE=""` explicitly disables loading for a testbench-owned memory. A nonempty missing path fails simulation. EXP/SIG files are readmemh/readmemb text, not vendor MIF syntax. Table index 0 corresponds to signed MIN; lane 0 and ternary weight 0 occupy the least significant bits.

## What the tests establish

- ALU: all 65536 input pairs for each 8-bit operation, all 32 lanes, selected flags; sampled 16-bit inputs and boundary cases. 524288 and 262144 output comparisons respectively.
- RAM/register: exact final beat, independent read ports, pauses, stable data during stalls, changing live descriptors, highest selectors, non-power-of-two depths, reset during transactions, and register selectors above seven at a wider leaf configuration.
- RMS: zero, constant, mixed MIN/MAX, impulse and nonuniform full vectors; input gaps, output stalls, and aborted capture.
- TMATMUL: identity, all-negative, sparse mixed signs, and all-positive matrices; signed MIN negation, positive/negative saturation, row/lane order, all 16 outputs, consecutive transactions, independent input gaps, held output and reset.
- DDR: lengths 0, 1, 2 and 15; upper addresses, rejected crossing of the address limit, changed descriptors, independent command/data stalls, UI reset/calibration loss, and restart.
- Core: 23 retired instructions per profile with a full-vector oracle at every commit, plus final checks of all eight registers, all vector banks and all eight matrix images. Includes in-place arithmetic, high-bank LDV/STV, NORM → STV → TMATMUL → LDV, and back-to-back TMATMUL.
- Control: 8192 decodes, all 512 HALT operand encodings, unknown-opcode side-effect checks, bounded PC at depth 3, and reset during load/store/RMS/TMATMUL.
- Guards: ten deliberately invalid configurations or missing-file cases per width; the expected fatal message is required. These expected failures are separate from passing functional simulations.

`tools/generate.py` creates reproducible numeric tables, a demonstration program and an independent vector reference. It checks LUT ordering, known values and high-precision Decimal references. These files provide arithmetic/integration evidence; they are not the thesis's missing trained weights, tokenizer or original executable workload.

No FPGA project constraints or synthesis/timing tool were available for this repair. The design has not been synthesized, timed, placed on a board or checked against a real MIG IP. The conservative instruction interlock and wide arithmetic require new resource/timing measurements.

## Historical evidence

`../scale/baseline` preserves the original 22 RTL files. `../review/audit_20260916` describes that snapshot. Review evidence runners now compile this preserved baseline. The old `scale/sim/tb_*.sv`, legacy logs and parameterization diff document the intermediate bug-preserving version; they are not the current acceptance suite. `../scale/run.ps1` forwards to the functional runner.
