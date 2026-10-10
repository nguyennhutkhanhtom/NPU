# Old FPGA timing backend

This is a preserved FPGA flow, not the current server ASIC flow. Read [timing and
evidence fundamentals](../../docs/00-start-here/fundamentals.md#from-rtl-to-evidence)
before comparing its Fmax or slack with Genus/ASIC results.

The local Quartus runner is retired on branch `remote`. FPGA evidence
is kept as is for source traceability; not applicable to new portable source.
Run Genus synthesis/report on Slurm according to [flow server](../server/README.md).
Mapped timing report needs constraint review; ASIC physical STA has not yet been applied.
