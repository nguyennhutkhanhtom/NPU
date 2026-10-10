// One-time validation for the documentation reading-map change.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const docs = path.join(root, 'docs');
const files = cp.execFileSync('rg', ['--files', 'docs', '-g', '*.md'],
  { cwd: root, encoding: 'utf8' }).trim().split(/\r?\n/).map(p => path.resolve(root, p));
const fresh = files.filter(p => p === path.join(docs, 'README.md') ||
  /[\\/](?:0[0-6]-[^\\/]+|decisions|archive)[\\/]/.test(p));
const content = new Map();
const read = p => {
  if (!content.has(p)) content.set(p, fs.readFileSync(p, 'utf8'));
  return content.get(p);
};
function links(p) {
  return [...read(p).matchAll(/!?\[[^\]\n]*\]\((<[^>]+>|[^)\n]+)\)/g)]
    .map(m => m[1].replace(/^<|>$/g, '').trim())
    .filter(s => !/^[a-z][a-z\d+.-]*:/i.test(s))
    .map(s => {
      const [file, fragment] = s.split('#');
      return { target: file ? path.resolve(path.dirname(p), decodeURIComponent(file)) : p,
        fragment: fragment && decodeURIComponent(fragment) };
    });
}
function anchors(p) {
  return [...read(p).matchAll(/^#{1,6}\s+(.+)$/gm)].map(m => m[1].trim()
    .toLowerCase().replace(/[^\p{L}\p{N}_\-\s]/gu, '').replace(/\s/g, '-'));
}
const errors = [];
let checked = 0;
for (const p of fresh) for (const link of links(p)) {
  checked++;
  if (!fs.existsSync(link.target)) errors.push(`${path.relative(root, p)}: missing ${link.target}`);
  else if (link.fragment && /\.md$/i.test(link.target) && !anchors(link.target).includes(link.fragment))
    errors.push(`${path.relative(root, p)}: missing anchor ${link.fragment}`);
}
const reachable = new Set();
const queue = [path.join(docs, 'README.md')];
while (queue.length) {
  const p = queue.shift();
  if (reachable.has(p)) continue;
  reachable.add(p);
  for (const { target } of links(p))
    if (target.startsWith(docs + path.sep) && /\.md$/i.test(target) &&
        fs.existsSync(target) && !reachable.has(target)) queue.push(target);
}
const orphaned = files.filter(p => !reachable.has(p));
console.log(JSON.stringify({ newOrUpdatedPages: fresh.length, checkedLinks: checked,
  markdownFiles: files.length, reachableMarkdownFiles: files.length - orphaned.length,
  errors, orphaned: orphaned.map(p => path.relative(root, p)) }, null, 2));
if (errors.length || orphaned.length) process.exitCode = 1;
