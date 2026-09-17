# Repair mapping and remaining limitations

The pre-repair workspace was clean at commit `49801c6`; all 23 current RTL hashes matched `scale/verification.json`. The interrupted earlier patch had applied no RTL changes. This repair implements functional behavior rather than preserving the known bugs.

| Review findings | Severity in review | Implemented correction | Evidence |
|---|---|---|---|
| F01, F02 | P1 / P2 | Correct ADD/SUB selection and carry/borrow; signed saturation; flags selected only from the active operation, including EXP saturation | ALU 8/16 |
| F03, F04 | P1 / P2 | Signed wide multiply/divide, correct fractional rescale, explicit rounding, zero-divisor and output-range handling | ALU 8/16, core |
| F05 | P1 | Full-domain signed EXP index; generated numeric tables and a checked saturation threshold | LUT audit, ALU 8/16, guards |
| F06 | P1 | Full-vector RMS statistics, guarded integer square root and signed division, buffered output transaction | RMS 8/16, core |
| F07–F12 | P1 / P2 | Width-safe bank addressing; latched descriptors; inclusive last beat; unified accepted-write condition; independent read valids; done pulses and direct reset | Storage 8/16, core |
| F13, F14 | P1 | Correct row-major unpacking; separate activation/weight valid-ready; bounded capture; all 16 accepted outputs before completion | TMATMUL 8/16, core |
| F15 | P1 / P2 | Sign extension before ternary negation, 26/18-bit reduction, one signed saturation at the result | TMATMUL MIN/overflow tests |
| F16–F19 | P2 | Latched DDR descriptors; zero-length no-op; buffered write data; per-command WDF END; distinct word/app address widths and range rejection; reset/calibration abort | DDR 8/16 |
| F20 | P1 | Generated numerical LUTs, reproducible executable test program, missing-file diagnostics and reference outputs | Asset hash/Decimal audit, core, guards |
| F21 | P1 | Propagated formats, corrected LUT/frame/accumulator widths, bounded PC, depth/pointer/packing guards and current scaled configuration | Both profiles; storage at exact minimum depth; guards |
| F22, F23 | P1 / P2 | Conservative complete-transaction interlock; pipeline beat valids; no flush of pending writeback; HALT by opcode after drain | Core, all HALT encodings, busy-reset tests |
| F24 | P2 | Exact opcode decode; invalid instructions cannot enable memory/register writes, with simulation failure at issue | Exhaustive decode, unknown opcode |
| F25–F27 | P1 | Correct stream routing; consistent STORE/TMATMUL vector locations; lane 0 at LSB; instruction context held through final accepted write | Core, TMATMUL, high-bank checks |

F20 is only **partly resolved**: the project now has usable numerical validation assets, but the original trained model, tokenizer and program images were not present. No original LLM workload accuracy claim is possible from generated test data.

The chosen numeric policies and clarified nonoverlapping memory map are detailed in [CONTRACT.md](CONTRACT.md). Old externally supplied RAM images must be repacked for matrix base 1024. The five-stage structure and parallel 512-row ternary reduction are retained; instruction overlap is conservatively serialized, so latency/throughput differ from the original intended scheduling.

One correction to the earlier DDR proposal: WDF END belongs to each MIG memory command's last UI data word. With the explicitly supported one-UI-word-per-command configuration it is asserted on every accepted WDF word, independently of the enclosing host request's length. Data is buffered and sent before the command, avoiding delayed-data timing after an accepted command. See AMD [command path](https://docs.amd.com/r/en-US/ug586_7Series_MIS/Command-Path) and [app_wdf_end](https://docs.amd.com/r/en-US/ug586_7Series_MIS/app_wdf_end?contentId=ZdZhrRlOYYPEGBvy0ty8og). Other MIG word/burst ratios need a corresponding adapter configuration or implementation and are not claimed supported.

The machine-readable result is [verification.json](verification.json). A PASS means the listed regression and source/asset checks completed; it is not formal equivalence, exhaustive full-processor verification or proof that no other bugs exist. Synthesis, timing closure, board tests and real MIG integration remain unverified.
