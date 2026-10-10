# NanoFable Assets pinned

> **Category: GUIDE.**

These files are inputs to export/reference/application flows, not an RTL result
by themselves. Read the [demo flow](../../docs/00-start-here/demo-flow.md) for how
checkpoint, tokenizer, integer reference, and returned RTL token IDs fit together.

[Documentation](../../docs/README.md) → [NanoFable Demo](../../docs/demos/language.md) → **Assets**

This folder provides checkpoint/tokenizer and dependencies for the application
llm_soc. Model revision, source revision, file sizes, and SHA-256 are in
[upstream_manifest.json](upstream_manifest.json).

## Download or verify

Run from the repository root with Python 3.11/3.12:

```powershell
$pythonExe = 'C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& tests/language_demo/setup.ps1 -Python $pythonExe
```

Set up by installing NumPy 2.3.5, safetensors 0.6.2, and tokenizers 0.22.1 into packages/
then download/verify 12 assets in upstream/. Checkpoints and packages are local,
git ignored. Setup step has not run model inference yet.

If the file already exists, check without re-downloading:

```powershell
& $pythonExe tests/language_demo/fetch_assets.py --check
```

To run the model, open the [NanoFable guide](../../docs/demos/language.md). Export and
CPU reference of the application only runs when the correct source/config has gone through all seven
units/graph groups and full-top all-corner timing gate.

## Previous hybrid evidence

[results.json](results.json) and [hybrid report](../../docs/demos/legacy/nanofable_hybrid.md)
retain CPU generation results along with linear-only RTL of the old flow. The hybrid runner has
been removed; this is historical evidence, not a full-graph application.
