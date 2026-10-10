const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const files = cp.execFileSync('git', ['diff', '--name-only', '--', 'docs'],
  { cwd: root, encoding: 'utf8' }).trim().split(/\r?\n/).filter(p => p.endsWith('.md'));
const requests = files.map(p => 'HEAD:'+p).join('\n')+'\n';
const snapshots = cp.execFileSync('git', ['cat-file', '--batch'],
  { cwd: root, input: requests, maxBuffer: 10*1024*1024 });
let offset = 0;
const errors = [];
const media = text => [...text.replaceAll('\r\n', '\n')
  .matchAll(/```[\s\S]*?```|!\[[^\]]*\]\([^\n]+\)/g)].map(m => m[0]);
for (const file of files) {
  const end = snapshots.indexOf(10, offset);
  const header = snapshots.subarray(offset, end).toString('utf8');
  const size = Number(header.split(' ').at(-1));
  if (!Number.isFinite(size)) throw Error(header);
  const before = snapshots.subarray(end+1, end+1+size).toString('utf8');
  offset = end+size+2;
  const after = fs.readFileSync(path.join(root, file), 'utf8');
  if (JSON.stringify(media(before)) !== JSON.stringify(media(after))) errors.push(file);
  if (file === 'docs/source_guide/blocks/README.md') {
    const targets = text => [...text.matchAll(/\]\(([^)]+\.sv\.md|[^)]+\.svh\.md|[^)]+\.mem\.md)\)/g)]
      .map(m => m[1]).sort();
    if (JSON.stringify(targets(before)) !== JSON.stringify(targets(after))) errors.push('Module catalog targets changed');
  }
}
console.log(JSON.stringify({ modifiedMarkdownPages: files.length,
  diagramsImagesAndCodeBlocks: errors.length ? 'FAIL' : 'unchanged',
  moduleCatalogTargets: 'checked', errors }, null, 2));
if (errors.length) process.exitCode = 1;
