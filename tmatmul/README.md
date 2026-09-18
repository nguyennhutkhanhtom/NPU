# ASIC ternary matrix multiplication

Current RTL is in `../Verilog Source code`. This change replaces the original fully unrolled TMATMUL with a pipelined, time-shared dot-product engine. `../functional` describes an older, different RTL interface and is not the acceptance suite for this revision. Run `./tmatmul/run.ps1` from the repository root; override `-SimBin` for another ModelSim installation. The simulator's Intel edition is used only for standard SystemVerilog simulation.

## Arithmetic and architecture

Weights are row-major two-bit codes: `01 = +1`, `11 = -1`, `00 = 0`. Reserved `10` contributes zero. Each product is a sign/zero selection; there is no binary multiplier. Activations are signed two's-complement integers or fixed-point raw values. Multiplication by a ternary integer preserves the activation binary point.

The default IP stores 512 activations and one 512-bit weight word. It computes 32 products per clock while issuing a row, reusing the engine for 512 rows. The former 524,288-bit internal weight store and 262,144 parallel product selectors are removed. Main memory remains outside the IP.

| Registered stage | Work |
|---|---|
| 0 | Read an activation group and select weight codes |
| 1 | Select `+x`, zero or `-x`, extending to DATA_WIDTH+1 **before** negation |
| 2 | Reduce groups of eight products to two carry-save words |
| 3 | Merge those words to one carry-save pair |
| 4 | Accumulate the pair with the saved row sum/carry through two 3:2 compressor levels |
| 5 | Perform one binary addition for the complete row |
| 6 | Quantize and pack the row into its output lane |

`acc_mul` is a combinational, parameterized 3:2 compressor tree. `acc_sum + acc_carry` equals the reduction modulo 2^ACC_WIDTH. The standalone `acc_result` supplies that final addition. TMATMUL uses the sum/carry ports, leaving the intermediate final adders unused. The default local and merge reductions each have four compressor levels between registers. The feedback stage contains no carry-propagating adder. Ordinary negation and the single final row addition occupy separate stages.

The full row accumulator defaults to `DATA_WIDTH + $clog2(MATRIX_COLS) + 1`, including space for `-MIN`. No intermediate saturation or truncation loses the exact row value. Output defaults to low-bit wrapping, as requested. `SATURATE=1` clamps only the final row to signed MIN/MAX. `overflow` is the OR of out-of-range row results in the current output word, in either mode.

Area is bounded by the activation buffer and a configurable dot-product engine. Data buffers and arithmetic pipeline registers are not reset; valid bits and a complete new activation load protect restart. All sequential logic uses the supplied clock and ordinary enables. There are no DSP blocks, vendor RAMs, generated clocks or FPGA attributes.

The engine drains its pipeline between rows, and pauses when a complete output word waits for acceptance. Without source/sink stalls, rows issue every `MATRIX_COLS/DOT_LANES + 6` clocks, with one additional handshake clock at output-word boundaries. The default complete frame takes approximately 11.3k clocks including activation loading. This intentionally trades frame latency for much smaller area and shorter register-to-register logic. Fmax remains a synthesis/STA measurement.

## Interface

`enable` is a one-cycle start request accepted only while `busy=0`. Input transfers begin on following cycles. Requests while busy are ignored. There is no command queue; pulse enable again for each frame. Reset aborts a frame and clears all valid/control state.

Both inputs use independent valid/ready handshakes. The source must keep data and valid stable until acceptance. Send `MATRIX_COLS/LANES` activation words, lane 0 in the least significant DATA_WIDTH bits. Send `ceil(MATRIX_ROWS*MATRIX_COLS/(DATA_WIDTH*LANES/2))` weight words, with the first weight in bits `[1:0]`. Rows continue across weight-word boundaries without per-row padding; unused weights at the end of the frame are ignored. Weights can arrive before activations, but backpressure applies once the one-word buffer fills.

`tmatmul_write` is output valid. Every transfer requires `tmatmul_write && output_ready`. The output word and overflow flag remain stable while stalled. There are `ceil(MATRIX_ROWS/LANES)` output transfers, with ascending rows from the least significant lane and zeros in unused lanes of the last word. Output can start before the full weight frame has arrived, so consumers must run concurrently with producers. `done` pulses for one cycle after the final output acceptance; `busy` clears at that same edge. `matrix_out` is unspecified when output valid is low.

This replaces the old `enable`-as-capture and `read_finish` interface. The sole production instantiation in `matmulfree.sv` is updated. It also fixes the old weight unpacking stride, reversed output lanes, input streams swapped at the integration boundary, and premature completion after the first result word.

## Parameters

| Parameter | Default | Requirement / effect |
|---|---:|---|
| DATA_WIDTH | 16 | Positive signed activation/output width |
| LANES | 32 | Positive activation/output word lane count |
| MATRIX_ROWS | 512 | Positive output row count; partial final word supported |
| MATRIX_COLS | 512 | Positive; multiple of LANES |
| DOT_LANES | 32 | Positive; divides LANES and the number of weights in a word |
| REDUCE_GROUP | 8 | Positive local group size; final group is zero padded |
| ACC_WIDTH | W+clog2(C)+1 | At least this many bits for full ternary precision |
| SATURATE | 0 | 0 wraps; 1 saturates at final output |

The packed word `DATA_WIDTH*LANES` must be even. Odd data widths work with a compatible DOT_LANES; for example W=7/LANES=32/DOT_LANES=16. Small dimensions require overriding DOT_LANES. Non-power-of-two legal dimensions, one-element configurations, and partial weight/output words are supported. Changing DOT_LANES/REDUCE_GROUP changes the area/throughput and timing balance; larger values need new timing checks.

The `acc_mul` input array remains descending. Its defaults are DATA_WIDTH=16, NUM_INPUTS=512, ACC_WIDTH=25. Its output width is now parameterized rather than fixed at 16; select `ACC_WIDTH=DATA_WIDTH` explicitly when standalone modulo addition is desired. For exact sums of ordinary signed operands, use at least `DATA_WIDTH+$clog2(NUM_INPUTS)`.

## Processor/memory integration

`mem_mapping.sv` adds a dedicated TMATMUL transaction path with independently buffered, synchronous reads and accepted-beat counters. It latches the matrix, activation and destination selectors, handles the final read/write beats, and does not restart a held request. The processor retains the following instruction until the final result is accepted, including back-to-back TMATMUL and HALT.

For TMATMUL, instruction `[2:0]` selects weights, `[5:3]` selects the activation vector, and `[8:6]` selects the destination. Activations and destinations occupy vector bank 0, starting at `selector*16`. Matrix storage starts at `1024 + selector*MATRIX_WORDS`, avoiding vector/matrix overlap. A 16-bit full matrix uses 1024 words, an 8-bit matrix uses 2048 words; memory images using the original overlapping addresses must be relocated. `mem_mapping` port 0 supplies weights, port 1 supplies activations.

The processor remains a fixed 16-bit, 32-lane, 512-element integration; the IP itself has the parameters above. The memory TM path also supports other DATA_WIDTH values for 512-element vectors, which the testbench exercises. Existing normal LDV/STV and unrelated arithmetic behavior are outside this repair. Their historical issues are not claimed fixed. The main memory is a behavioral storage model; an ASIC integration can supply streams from its SRAM/controller and synthesize the standalone IP without the large processor memory model. `INIT_FILE` on mem_mapping is now a simulation-only preload, not an ASIC power-up guarantee.

## Verification and synthesis

`verification.json` records the tests and source hashes for the last complete run. The suite checks independent mathematical row sums before quantization, output values/overflow, identity and mixed signs, all-positive/all-negative extremes, exact cancellation, reserved codes, bubbles, busy starts, resets during capture/compute/stalled output, and consecutive frames. It includes exhaustive 4-bit two-term arithmetic, accumulator trees with irregular operand counts, 8/16-bit full 512x512 frames in both quantization modes, and 1/4/7/12/24/32-bit configurations with varied shapes and reduction groups. Memory tests cover independent backpressure, descriptor changes, highest selectors, partial weight words and in-place results. The real processor test executes three consecutive TMATMUL instructions and drains before HALT; it uses all real RTL modules with a smaller simulation memory, not a ternary stub. Zero-valued inactive EXP/SIG table fixtures are only for elaborating that integration test.

`synth/genus.tcl` reads only `acc_mul.sv` and `ternary_mul.sv`, maps to supplied standard-cell Liberty libraries, and writes timing, area, gates, constraints and design-check reports. It requires `TM_LIBS` (Tcl list of library paths) and `TM_SDC` (constraints file path); optional `TM_PARAMETERS` accepts named parameter/value pairs and `TM_OUT` selects the report directory. `synth/example.sdc` is an illustrative timing budget, not a timing result. Use the matching library corner, drive/load, reset recovery/removal requirements, and integration constraints for your chip. Inspect inferred storage, latches, unresolved/multidriven nets, unconstrained paths and mapped cells before accepting a run.

The scripting flow follows [Cadence's synthesis example](https://community.cadence.com/cadence_technology_forums/f/digital-implementation/55520/genus-standard-cells-to-module) and the [TILOS research flow](https://github.com/TILOS-AI-Institute/MacroPlacement/blob/main/Flows/scripts/cadence/run_genus.tcl). **Genus and a standard-cell library were not available here. This script has not been executed in Genus, and no mapped area, power, slack or Fmax improvement is claimed.** RTL simulation and the structural pipeline changes are the evidence delivered here; characterized PPA needs the target synthesis and physical-design flow.
