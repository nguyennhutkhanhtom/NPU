# NanoFable assets and historical evidence

[Documentation hub](../../docs/README.md) · [Full RTL application](../full_rtl/README.md) · [Historical hybrid report](../../docs/demos/language.md)

This directory provides the pinned checkpoint/tokenizer and scoped dependencies
used by the full RTL application. CPU reference computation is verification only.
The application runner checks current synthesis, fitting, all-corner timing at
100 MHz, six unit groups and exact source/configuration hashes before execution.

```powershell
./tests/language_demo/setup.ps1 -Python 'C:/path/to/python312/python.exe'
# Only after all current hardware/unit gates pass:
./tests/full_rtl/run_application.ps1 -TimingManifest docs/verification/timing/PASS_TAG/manifest.json
```

Setup installs NumPy2.3.5, safetensors0.6.2 and tokenizers0.22.1 under `packages/`,
then fetches and verifies the 12 assets in [upstream_manifest.json](upstream_manifest.json).
Checkpoint, tokenizer, upstream source, packages and build caches stay local.
`fetch_assets.py --check` verifies existing files without downloading or running a model.

The former hybrid exporter/runner/testbench has been removed: it computed the
graph on CPU and replayed only linears on RTL. [results.json](results.json) and the
historical report retain its scope and measurements; they cannot satisfy full RTL
application gates. The deleted scripts remain recoverable at Git commit
`d9ed7921d42731a198f565785a8ae79b20c7c79e`.
