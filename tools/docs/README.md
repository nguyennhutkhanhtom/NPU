# Documentation diagram tools

> **Category: GUIDE.** Short entry point. Full details (environment overrides, hierarchy rules,
> validation scope): [diagram rendering guide](../../docs/diagrams/rendering.md).

Run from the repository root with Node.js 20 or newer:

```powershell
npm ci --prefix tools/docs
npx --prefix tools/docs playwright install chromium
node tools/docs/render.cjs
```

Hierarchy diagrams:

```powershell
python tools/docs/build_hierarchy.py
node tools/docs/preview_hierarchy.cjs
python tools/docs/validate_hierarchy.py
```

Rendering checks Mermaid syntax only; it does not run RTL regression.
