# Retired Quartus experiments

Eleven retired project folders now live under `quartus/archive/`. Their QPF,
QSF, SDC and raw reports were verified byte-for-byte after relocation.
Current builds use `quartus/llm_soc`; these snapshots do not participate in it.

| Original folder | Current local folder |
|---|---|
| `quartus_attention1` | `quartus/archive/quartus_attention1` |
| `quartus_cache1` | `quartus/archive/quartus_cache1` |
| `quartus_cache2` | `quartus/archive/quartus_cache2` |
| `quartus_explicit1` | `quartus/archive/quartus_explicit1` |
| `quartus_explicit2` | `quartus/archive/quartus_explicit2` |
| `quartus_fanout1` | `quartus/archive/quartus_fanout1` |
| `quartus_fanout2` | `quartus/archive/quartus_fanout2` |
| `quartus_logic5` | `quartus/archive/quartus_logic5` |
| `quartus_logic6` | `quartus/archive/quartus_logic6` |
| `quartus_logic7` | `quartus/archive/quartus_logic7` |
| `quartus_pipeline1` | `quartus/archive/quartus_pipeline1` |

The original relative QSF paths remain unchanged for provenance. To reproduce
an old experiment, reconstruct its original layout from the immutable source ZIP
and recorded configuration/commands under `docs/verification/timing`, using a
fresh output tag. These folders remain local-only under the existing ignore rule.

[Move record](workspace_arrangement_20261005.json) · [Current backend](../../quartus/README.md)
