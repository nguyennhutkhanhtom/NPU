# Quartus timing tools

> **Category: GUIDE.** Short entry point. Full procedure, evidence rules and extraction options:
> [timing tools guide](../../docs/verification/timing_tools.md). How to read results:
> [timing guide](../../docs/verification/timing/README.md).

Run from the repository root. Use a fresh `-Tag` for every run; earlier evidence is preserved.

```powershell
./tools/timing/run.ps1 -Project quartus/llm_soc -Tag my_timing_tag -QuartusBin 'C:/altera_lite/25.1std/quartus/bin64'
```

| File | Purpose |
|---|---|
| `run.ps1` | Compile, post-fit STA, extract four corners, record evidence under `docs/verification/timing/<tag>` |
| `extract.tcl` | Extract reports from an existing routed database |
| `record.py` | Record a completed manual compile from its source snapshot |
| `archive_sources.py` | Add a source ZIP when every RTL hash still matches `sources_before.json` |

Quartus timing is FPGA evidence only, not ASIC timing.
