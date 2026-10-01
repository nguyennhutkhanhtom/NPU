const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
const docs = path.join(root, 'docs');
const output = path.join(__dirname, 'output');
const guide = path.join(docs, 'source_guide');

function markdownFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true })
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(item => item.isDirectory() ? markdownFiles(path.join(directory, item.name))
      : item.name.endsWith('.md') ? [path.join(directory, item.name)] : []);
}

const files = markdownFiles(docs);
if (fs.existsSync(path.join(root, 'README.md'))) files.unshift(path.join(root, 'README.md'));
const diagrams = [];
for (const file of files) {
  let ordinal = 0;
  for (const match of fs.readFileSync(file, 'utf8').matchAll(/```mermaid\r?\n([\s\S]*?)\r?\n```/g)) {
    diagrams.push({ file: path.relative(root, file).replaceAll('\\', '/'), ordinal: ordinal++, code: match[1] });
  }
}

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const launch = { headless: true };
  if (process.env.DOCS_BROWSER_PATH) launch.executablePath = process.env.DOCS_BROWSER_PATH;
  const browser = await chromium.launch(launch);
  const page = await browser.newPage({ viewport: { width: 1800, height: 1100 }, deviceScaleFactor: 1 });
  try {
    await page.setContent('<!doctype html><html><head><meta charset="utf-8"><style>body{margin:0;background:white;font-family:Arial,sans-serif}#diagram{display:inline-block;padding:20px}svg{max-width:none!important}</style></head><body><div id="diagram"></div></body></html>');
    const suppliedMermaid = process.env.DOCS_MERMAID_PATH;
    let mermaidVersion;
    if (suppliedMermaid) {
      mermaidVersion = process.env.DOCS_MERMAID_VERSION || 'external bundle (version not supplied)';
      await page.addScriptTag({ path: suppliedMermaid });
    } else {
      const moduleDirectory = path.dirname(require.resolve('mermaid'));
      mermaidVersion = JSON.parse(fs.readFileSync(path.join(moduleDirectory, '..', 'package.json'), 'utf8')).version;
      const bundle = path.join(moduleDirectory, 'mermaid.min.js');
      if (fs.existsSync(bundle)) {
        await page.addScriptTag({ path: bundle });
      } else {
        await page.route('https://npu-docs.local/mermaid/**', async route => {
          const relative = decodeURIComponent(new URL(route.request().url()).pathname.slice('/mermaid/'.length));
          const file = path.resolve(moduleDirectory, relative);
          if (!file.startsWith(moduleDirectory + path.sep) || !fs.existsSync(file)) {
            await route.abort();
            return;
          }
          await route.fulfill({ path: file, contentType: 'application/javascript', headers: { 'Access-Control-Allow-Origin': '*' } });
        });
        await page.addScriptTag({ type: 'module', content: 'import mermaid from "https://npu-docs.local/mermaid/mermaid.esm.min.mjs"; window.mermaid = mermaid;' });
        await page.waitForFunction(() => Boolean(window.mermaid));
      }
    }
    await page.evaluate(() => mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'neutral', fontFamily: 'Arial, sans-serif', flowchart: { htmlLabels: true, useMaxWidth: false, nodeSpacing: 28, rankSpacing: 35, curve: 'linear' }, themeVariables: { fontSize: '16px' } }));
    const results = [];
    for (let i = 0; i < diagrams.length; i++) {
      const d = diagrams[i];
      const key = String(i).padStart(2, '0') + '-' + d.file.replaceAll(/[^a-zA-Z0-9.-]/g, '_') + '-' + d.ordinal;
      try {
        const result = await page.evaluate(async ({ code, key }) => {
          await mermaid.parse(code);
          const rendered = await mermaid.render('g' + key.replaceAll(/[^a-zA-Z0-9]/g, ''), code);
          document.getElementById('diagram').innerHTML = rendered.svg;
          const svg = document.querySelector('#diagram svg');
          const b = svg.viewBox.baseVal;
          svg.style.width = Math.ceil(b.width) + 'px';
          svg.style.height = Math.ceil(b.height) + 'px';
          return { svg: rendered.svg, width: Math.ceil(b.width), height: Math.ceil(b.height), nodes: svg.querySelectorAll('.node').length };
        }, { code: d.code, key });
        fs.writeFileSync(path.join(output, key + '.svg'), result.svg);
        await page.locator('#diagram').screenshot({ path: path.join(output, key + '.png'), timeout: 15000 });
        results.push({ file: d.file, ordinal: d.ordinal, source_sha256: crypto.createHash('sha256').update(d.code.replaceAll('\r\n', '\n')).digest('hex'), width: result.width, height: result.height, nodes: result.nodes, status: 'rendered' });
      } catch (error) {
        results.push({ file: d.file, ordinal: d.ordinal, status: 'failed', error: String(error) });
      }
    }
    fs.writeFileSync(path.join(guide, 'diagram_validation.json'), JSON.stringify({ verified_date: new Date().toISOString().slice(0, 10), mermaid_version: mermaidVersion, scope: 'Mermaid parse and render of every diagram in docs Markdown and the repository README. This records diagram evidence only; RTL regression and synthesis evidence are recorded separately.', diagrams: results }, null, 2) + '\n');
    console.log(JSON.stringify({ total: results.length, rendered: results.filter(r => r.status === 'rendered').length, failures: results.filter(r => r.status === 'failed') }));
    process.exitCode = results.some(r => r.status === 'failed') ? 1 : 0;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
