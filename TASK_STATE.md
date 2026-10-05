# Current workspace checkpoint

Updated 2026-10-05, Asia/Saigon. Sources and recorded evidence are authoritative.
Preserve existing changes and immutable evidence; follow [AGENTS.md](AGENTS.md).

The approved exact throughput optimization is complete. Current RTL/LUT assets
match all-seven unit/graph, host cancellation, portable elaboration and full-top
post-fit timing PASS evidence. Synthetic graph: 1,066,965 compute clocks versus
4,254,046 at task start, 3.987x speedup. Minimum Fmax is 100.78 MHz at all four
corners, nonnegative setup/hold/recovery/removal/pulse slack, TNS zero and no
unconstrained paths. No pretrained application was executed.

- [Implementation report](docs/reviews/rtl_change_review_v3.md)
- [Current evidence and reproduction commands](docs/verification/optimization_status.md)
- [Active Quartus project](quartus/README.md)
- [Research reference](docs/design/architecture_research.md)
- [Retired Quartus project locations](docs/history/quartus_projects.md)
- [Historical task state from 2026-10-04](docs/history/task_state_20261004.md)

Current source/configuration paths are unchanged. The `opt_final4` compiled unit
library and verified RAM model remain available. Inactive caches were removed;
historical one-shot scripts are archived. The prior task-state file is preserved
byte-for-byte; its links and commands use the original repository-root context.

The current backend is an EDA demonstration. Quartus results are not ASIC signoff.
