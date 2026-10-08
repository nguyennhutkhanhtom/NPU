# Quartus EDA backend

> Backend FPGA lịch sử, không còn là flow chạy hiện tại trên branch `remote`. Xem [flow server](../tools/server/README.md).


> **Category: GUIDE.**

The active full-graph project is `llm_soc.qpf`, with `llm_soc.qsf` and
`llm_soc.sdc`. The legacy `matmul_free` project retains its separate configuration.
Portable compute/control RTL stays in `Verilog Source code`; backend device,
I/O and placement assignments stay here.

From the repository root:

```powershell
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag FRESH_TAG -QuartusBin C:/altera_lite/25.1std/quartus/bin64
```

`archive/` holds eleven retired experiment folders, with configurations and
raw output files preserved byte-for-byte. These local snapshots are ignored by
Git. Their original QSF relative paths describe their original locations;
do not build them in place after relocation. Use their preserved source/config
archives and recorded commands under `docs/verification/timing` for a fresh replay.

Trạng thái source/config hiện tại: [verification status](../docs/verification/optimization_status.md).
Current verification and implementation status: [optimization status](../docs/verification/optimization_status.md).
Experiment locations: [historical project index](../docs/history/quartus_projects.md).
Quartus results are an EDA demonstration, not ASIC signoff.
