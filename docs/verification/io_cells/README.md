# Ordinary I/O cell characterization

> **Category: GUIDE.**

[Documentation hub](../../README.md) · [Full-top timing](../timing/README.md) · [ASIC portability](../../design/asic_portability.md)

These probes measure physical I/O buffers on the selected FPGA. They are not
full-graph synthesis/timing acceptance or application demonstrations.

[LVDS output evidence](lvds_output18/manifest.json) archives 51 original files
in a hashed ZIP, including source, QSF/QPF/SDC, map/fit/STA reports and all four
corners. The eight-FF probe uses Cyclone V `5CGXFC9E6F35C7`, Quartus Lite18.1,
a single-ended2.5V clock on AC18, and ordinary parallel SDR LVDS output buffers.
Fitter creates each negative companion. There is no ALTLVDS, serializer or PLL;
the fitted DSP/PLL/DLL/HSSI counts are zero. Recovery/removal do not apply because
the probe has no reset. All setup/hold/pulse checks have TNS0 and unconstrained0.

| Corner1.1V | Setup ns | Hold ns | Pulse ns |
|---|---:|---:|---:|
| Slow85C | .422 | .692 | 4.069 |
| Slow0C | .380 | 2.701 | 4.030 |
| Fast85C | 3.951 | 1.936 | 4.422 |
| Fast0C | 4.088 | .631 | 4.408 |

The measured Slow0C worst path has output-clock insertion5.553ns and data1.967ns
(FF clock-to-output.634ns plus true LVDS buffer1.333ns). Both positive and
negative physical outputs are analyzed. The archived probe helper reproduces
the original18.1 experiment when that tool is available; it is not the current
full-top runner. The installed full-top tool is now25.1std, so the current design
must establish its own result on that version. Board routing/termination is
outside this probe; the host must accept a differential parallel bus.
