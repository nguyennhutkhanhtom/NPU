# Render documentation diagrams

[Documentation hub](../../docs/README.md) · [Source guide](../../docs/source_guide/README.md)

The Markdown Mermaid blocks are the source of truth. This renderer scans all
Markdown under `docs/` and the root `README.md`, checks syntax, saves PNG/SVG
previews under the ignored `output/` folder, and records source hashes in
`docs/source_guide/diagram_validation.json`.

## Setup and run

Install Node.js 20 or newer, then run from the repository root:

```powershell
npm ci --prefix tools/docs
npx --prefix tools/docs playwright install chromium
node tools/docs/render.cjs
python docs/source_guide/validate.py
```

Dependencies are pinned in [package.json](package.json) and
[package-lock.json](package-lock.json): Mermaid 11.17.2 and Playwright 1.62.1.
They are installed only in this tool directory.

To use an existing browser executable instead of a Playwright browser download:

```powershell
$env:DOCS_BROWSER_PATH = 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'
node tools/docs/render.cjs
```

`NODE_PATH` can select an existing Playwright installation. For a preinstalled
Mermaid browser bundle, set `DOCS_MERMAID_PATH` to its local path. Omit these
environment overrides when using the dependencies installed above.
For an external Mermaid bundle, set `DOCS_MERMAID_VERSION` to its version so the
render evidence records that version accurately.

Successful rendering verifies the diagrams and current Markdown hashes; it does
not run RTL regression or establish ASIC timing.
