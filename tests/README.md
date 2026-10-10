# Test System

> **Category: GUIDE.**

[Home page](../README.md) · [Document table of contents](../docs/README.md) · [Verification results](../docs/verification/README.md) · [Model demos](../docs/demos/README.md)

## Choose a validator

| Design | Entry point on Linux Slurm | Guide |
|---|---|---|
| llm_soc units/graph/probes | `tools/server/run_flow.py --stage test` | [Flow server](../tools/server/README.md) |
| llm_soc checkpoint | `--stage application --fixture PATH` | [Flow server](../tools/server/README.md#application-checkpoint) |
| matmulfree legacy | `--stage legacy` | [Flow server](../tools/server/README.md) |

## Regression legacy

Legacy runner compile in the same directory as the Verilog Source code and use tb_all.sv.
The results of this set belong to core matmulfree; the full graph llm_soc has seven separate groups.

Xcelium runs the tops in `tb_all.sv`; Python integer/Decimal generates vectors
in each top's own database. No local test tool is needed. Choose the list
of legacy tops in `tools/server/flow.json`; the current runner runs 9 full tops.
The blocks/coverage below are the contract of the fixtures kept unchanged.

| Block | Content |
|---|---|
| All | Eight testbenches on the same RTL and checking ROM with Python |
| Host | All 168 integration cases via host: NORM, TMATMUL, vector, dynamic scale, descriptor, and address |
| Norm | NORM/QUANT, K=1…512, packing/tail, zero/full-scale, epsilon/delta, overlap and bounds |
| Ternary | Weight by chunk, S8 extrema, bias/no-bias, S16/S32, NORM→TMATMUL, scale disabled and wrong descriptor |
| Rowwise | ADD/SUB/MUL/SIG/REC/RELU, shift, RNE, saturation, unsigned gate, tail and overlap |
| Scalar | Divider U64, sqrt 0…4095 and square border ±1, RNE, exact scale composition U128, reset/start when busy |
| DivProfiles | NUM/DEN=1/1, 7/3, 3/7, 64/32, 64/64; exhaustive small widths, quotient/remainder, zero and input capture |
| Postscale | ACC18×U24, RNE shift 0…63, bias S32, saturation S16/S32, extrema and random |
| Sigmoid | 1,638,400 S16 values to cover F=0…24 via ROM constant in `sigmoid_lut.svh`; reset/start when busy |
| Sram | 47 latency checks for two clocks, address switching, lane masking, compute read and reset hold memory |
| Imem | 1,027 checks: 512 addresses, client switch, synchronous valid, overwrite/re-read, restart/reset |
| Arithmetic | Reduction tree, helper addsub/mul, boundaries and random |
| AccMul / AddSub / Mul | Select individual arithmetic tasks in `tb_arithmetic` |

Each top has its own database/log in `build/TAG` and `reports/TAG`.

`reference.py` recreates the vector using Python integer/Decimal and verifies accurately 257 samples of both `.mem` and `.svh`, including monotonicity and consecutive sample differences not exceeding 512. It also checks that the validator rejects each asset with missing or incorrect 128-sample data: two missing cases and two faulty cases, using simulated input in Python. RTL always uses ROM constants, with no parameters to change the LUT file.

Scale composition is compared including `(M,r)` with independent U128 division/rounding, finding the largest `r` in 0…47. Cases cover underflow/overflow, U24 RNE limits, midpoint and both sides of the midpoint; valid transactions must complete within 128 clocks. Sqrt checks `root² ≤ x < (root+1)²` using U66 multiplication with 32 clock latency. Other tests change input/pulse `start` when busy and reset during a transaction to check capture/cancel/restart.

Host cases include additional NORM overflow and then incorrect descriptor without reset (new overflow must be 0 and output remains), reset while divider NORM is busy and then restart, same/partial alias of NORM q is rejected if using static scale and the address immediately after q extent is still valid.

Current synthesis uses Genus for `llm_soc` and Liberty provided by the lab.
`check_synthesis.tcl` and the old PowerShell runner return errors directing to the flow server.
The legacy result does not verify the checkpoint for the entire graph or ASIC signoff.

Incompatible test v1 has been discarded. The remaining useful arithmetic cases from the old set have been moved to the new interface: reduction N=1/3/32/37/512, negative numbers and extrema, saturation, signed/unsigned multiplication, and RNE.

## Demo checkpoint

- [Full graph NanoFable](../docs/demos/language.md): real checkpoint and application gate for llm_soc.
- [NanoFable assets](language_demo/README.md): setup, pinned files, and dependencies.
- [Legacy demo](../docs/demos/legacy/README.md): MNIST and saved NanoFable hybrid.

Dependencies and build cache are local, separated from the source. See
[verification status](../docs/verification/optimization_status.md) before
running pretrained export/reference/application.
