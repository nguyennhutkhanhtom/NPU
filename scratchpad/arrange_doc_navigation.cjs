// Mechanical navigation rewrite; technical text and diagram content are retained.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const files = cp.execFileSync('rg', ['--files', 'docs', '-g', '*.md'],
  { cwd: root, encoding: 'utf8' }).trim().split(/\r?\n/).map(p => p.replaceAll('\\', '/'));
const write = process.argv.includes('--write');
const tidy = process.argv.includes('--tidy');
const refreshModules = process.argv.includes('--refresh-modules');
const catFile = 'docs/source_guide/blocks/README.md';
const catalog = fs.readFileSync(path.join(root, catFile), 'utf8');
const scope = new Map();
for (const line of catalog.split(/\r?\n/)) {
  const m = line.match(/^\| \[([^\]]+)\].*?\| (Full graph|Shared|Legacy|Helper|Asset) \|/);
  if (m) scope.set(m[1] + '.md', m[2]);
}
const D = 'docs/';
const system = D + '01-system/README.md', arch = D + '02-architecture/README.md';
const model = D + '03-model/README.md', verify = D + '04-verification/README.md';
const impl = D + '05-implementation/README.md', research = D + '06-research/README.md';
const archive = D + 'archive/README.md', decisions = D + 'decisions/README.md';
const graph = D + 'source_guide/full_graph.md', numeric = D + 'design/full_rtl_language.md';
const status = D + 'verification/optimization_status.md';
const index = D + 'source_guide/blocks/README.md';
const legacy = D + 'design/legacy/architecture.md';
const moduleNext = {
  'llm_soc.sv': 'llm_linear_engine.sv', 'llm_pkg.sv': 'llm_soc.sv',
  'llm_linear_engine.sv': 'ternary_dot32.sv', 'ternary_dot32.sv': 'llm_math.sv',
  'llm_math.sv': 'logic_mul.sv', 'llm_head_engine.sv': 'llm_parameter_ram.sv',
  'llm_attention_engine.sv': 'llm_attention_normalize.sv', 'llm_attention_normalize.sv': 'div.sv',
  'llm_exp_lut.svh': 'llm_attention_engine.sv', 'llm_gumbel_lut.svh': 'llm_soc.sv',
  'llm_bank_ram.sv': 'pipelined_word_ram.sv', 'llm_parameter_ram.sv': 'sram_word_tile.sv',
  'pipelined_word_ram.sv': 'sram_word_tile.sv', 'sram_word_tile.sv': 'quartus_word_ram.sv',
  'quartus_word_ram.sv': 'sram_word_tile.sv', 'reset_release.sv': 'llm_soc.sv',
  'div.sv': 'llm_attention_normalize.sv', 'isqrt_u64.sv': 'llm_soc.sv',
  'logic_mul.sv': 'llm_math.sv', 'npu_pkg.sv': 'llm_pkg.sv',
  'sigmoid.sv': 'sigmoid_lut.svh', 'sigmoid_lut.svh': 'sigmoid.sv',
  'sigmoid_257.mem': 'sigmoid_lut.svh', 'mul.sv': 'logic_mul.sv',
  'matmulfree.sv': 'descriptor_file.sv', 'matmul_wrap.sv': 'matmulfree.sv',
  'descriptor_file.sv': 'rowwise_dispatch.sv', 'ins_mem.sv': 'PC.sv', 'PC.sv': 'ins_mem.sv',
  'acc_mul.sv': 'ternary_mul.sv', 'ternary_mul.sv': 'postscale.sv',
  'postscale.sv': 'scale_compose.sv', 'scale_compose.sv': 'npu_pkg.sv',
  'rowwise_dispatch.sv': 'rowwise_op.sv', 'rowwise_op.sv': 'sigmoid.sv',
  'norm_dispatch.sv': 'norm.sv', 'norm.sv': 'isqrt_u64.sv',
  'mem_mapping.sv': 'sram_256_wrapper.sv', 'regfile.sv': 'sram_256_wrapper.sv',
  'sram_256_wrapper.sv': 'banked_word_ram.sv', 'banked_word_ram.sv': 'sram_word_tile.sv',
};
const special = {
  'docs/design/full_rtl_language.md': [system, '01 · System', D+'00-start-here/quickstart.md', 'Quickstart', graph, 'Full RTL graph'],
  'docs/source_guide/full_graph.md': [arch, '02 · Architecture', numeric, 'System architecture', index, 'Module catalog'],
  'docs/design/host_interface.md': [arch, '02 · Architecture', numeric, 'System architecture', D+'source_guide/blocks/llm_soc.sv.md', 'Controller implementation'],
  'docs/design/exact_throughput_optimization.md': [research, '06 · Research', numeric, 'Architecture and numeric contracts', status, 'Measured results and evidence'],
  'docs/design/asic_portability.md': [impl, '05 · Implementation', arch, 'Architecture map', D+'design/asic_memory_binding.md', 'SRAM binding contract'],
  'docs/design/asic_memory_binding.md': [impl, '05 · Implementation', D+'design/asic_portability.md', 'ASIC portability', D+'source_guide/blocks/sram_word_tile.sv.md', 'Portable SRAM implementation'],
  'docs/design/rtl_style.md': [decisions, 'Decisions', arch, 'Architecture map', D+'reviews/rtl_lowrisc_readiness_20261010.md', 'Coding readiness review'],
  'docs/demos/language.md': [D+'00-start-here/README.md', '00 · Start here', D+'00-start-here/demo-flow.md', 'Demo reading flow', 'tools/server/README.md#application-checkpoint', 'Current server application workflow'],
  'docs/demos/candidates.md': [model, '03 · Model', numeric, 'Geometry and numerical contracts', D+'00-start-here/demo-flow.md', 'Checkpoint demo flow'],
  'docs/verification/optimization_status.md': [verify, '04 · Verification', D+'verification/README.md', 'Verification gates', D+'NPU_V2_EXECUTION.md', 'Execution milestones'],
  'docs/NPU_V2_EXECUTION.md': [decisions, 'Decisions', numeric, 'Architecture contract', status, 'Matching verification evidence'],
  'docs/verification/timing/README.md': [impl, '05 · Implementation', status, 'Current evidence and backend scope', D+'history/timing_development.md', 'Historical FPGA timing development'],
  'docs/diagrams/diagram_style.md': [decisions, 'Decisions', D+'diagrams/README.md', 'Diagram index', D+'diagrams/architecture_catalog.md', 'Editable diagram catalog'],
};
function route(file) {
  if (special[file]) return special[file];
  if (/\/(history|legacy)\//.test(file) || /verification\/(npu100_b1_baseline|optimization_baseline)\//.test(file) || /verification\/(nanofable_max|warning_review)/.test(file))
    return [archive, 'Archive', /\/legacy\//.test(file) ? legacy : archive, /\/legacy\//.test(file) ? 'Legacy architecture' : 'Historical context', status, 'Current evidence'];
  if (file.startsWith(D+'source_guide/blocks/')) {
    const s = scope.get(path.posix.basename(file));
    const next = moduleNext[path.posix.basename(file, '.md')];
    return [s === 'Legacy' ? archive : arch, s === 'Legacy' ? 'Archive · Legacy' : '02 · Architecture', s === 'Legacy' ? legacy : graph, s === 'Legacy' ? 'Legacy architecture' : 'Full RTL graph', next ? D+'source_guide/blocks/'+next+'.md' : index, next ? next+' · related implementation' : 'Other module guides'];
  }
  if (file.startsWith(D+'source_guide/')) return [arch, '02 · Architecture', numeric, 'System architecture', index, 'Module catalog'];
  if (file.startsWith(D+'design/')) return [arch, '02 · Architecture', system, 'System map', index, 'Module catalog'];
  if (file.startsWith(D+'diagrams/') || file === D+'all_docs.md') return [system, '01 · System', graph, 'Full RTL graph', D+'diagrams/architecture_catalog.md', 'Editable diagram catalog'];
  if (file.startsWith(D+'demos/')) return [model, '03 · Model', D+'00-start-here/demo-flow.md', 'Demo reading flow', D+'demos/candidates.md', 'Model compatibility'];
  if (file.startsWith(D+'reviews/')) return [decisions, 'Decisions', D+'NPU_V2_EXECUTION.md', 'Execution contract', status, 'Matching verification evidence'];
  if (file.startsWith(D+'verification/')) return [verify, '04 · Verification', D+'verification/README.md', 'Verification gates', status, 'Current evidence'];
  throw Error('Unclassified document: ' + file);
}
function link(from, target, title) {
  const [file, fragment] = target.split('#');
  const rel = path.posix.relative(path.posix.dirname(from), file) || path.posix.basename(file);
  return `[${title}](${rel}${fragment ? '#'+fragment : ''})`;
}
const changes = [];
let removedBreadcrumbs = 0;
for (const file of files) {
  if (file === D+'README.md' || /^docs\/(0[0-6]-[^/]+|archive|decisions)\//.test(file)) continue;
  const absolute = path.join(root, file);
  const original = fs.readFileSync(absolute, 'utf8');
  if (original.includes('<!-- reading-navigation:start -->')) {
    if (refreshModules && file.startsWith(D+'source_guide/blocks/') && file !== catFile) {
      const r = route(file);
      const block = [ '<!-- reading-navigation:start -->',
        `${link(file, D+'README.md', 'Documentation')} → ${link(file, r[0], r[1])} → ${link(file, index, 'Module catalog')}`,
        '', '| Reading guide | Document |', '|---|---|',
        `| Read first | ${link(file, r[2], r[3])} |`,
        `| Related implementation | ${link(file, r[4], r[5].replace(' · related implementation', ''))} |`,
        '<!-- reading-navigation:end -->' ].join(original.includes('\r\n') ? '\r\n' : '\n');
      const updated = original.replace(/<!-- reading-navigation:start -->[\s\S]*?<!-- reading-navigation:end -->/, block);
      changes.push(file);
      if (write) fs.writeFileSync(absolute, updated);
    }
    if (tidy) {
      const marker = '<!-- reading-navigation:end -->';
      const end = original.indexOf(marker) + marker.length;
      const prefix = original.slice(0, end);
      let suffix = original.slice(end).replace(/^(?:\r?\n){3,}/, '\n\n');
      const split = suffix.search(/^## /m);
      const introEnd = split < 0 ? suffix.length : split;
      suffix = suffix.slice(0, introEnd).replace(/(?:\r?\n){3,}/g, '\n\n') + suffix.slice(introEnd);
      let updated = prefix + suffix;
      if (file === 'docs/history/task_state_20261004.md') updated = updated.replaceAll('\r\n', '\n');
      if (updated !== original) {
        changes.push(file);
        if (write) fs.writeFileSync(absolute, updated);
      }
    }
    continue;
  }
  const newline = original.includes('\r\n') ? '\r\n' : '\n';
  const lines = original.split(/\r?\n/);
  const h1 = lines.findIndex(line => /^# /.test(line));
  if (h1 < 0) throw Error('Missing title: '+file);
  const r = route(file);
  const rows = [
    '<!-- reading-navigation:start -->',
    `${link(file, D+'README.md', 'Documentation')} → ${link(file, r[0], r[1])} → ${file === catFile ? 'Module catalog' : 'This page'}`,
    '', '| Reading guide | Document |', '|---|---|',
  ];
  if (r[2] !== file) rows.push(`| Read first | ${link(file, r[2], r[3])} |`);
  if (r[4] !== file) rows.push(`| Continue / related lookup | ${link(file, r[4], r[5])} |`);
  rows.push('<!-- reading-navigation:end -->');
  // Remove only old standalone breadcrumbs in the introductory region.
  for (let i = Math.min(lines.length-1, h1+16); i > h1; i--) {
    if (/^\[(?:Documentation|Document|Tài liệu|Design|Source guide|Project)\]/.test(lines[i]) &&
        /→| · /.test(lines[i]) && !/Editable draw\.io/.test(lines[i])) {
      lines.splice(i, 1); removedBreadcrumbs++;
    }
  }
  lines.splice(h1+1, 0, '', ...rows, '');
  let updated = lines.join(newline);
  if (file === catFile) {
    const tableLines = updated.split(newline);
    const start = tableLines.findIndex(l => l.startsWith('| Source | Scope | Role | Notes |'));
    if (start < 0) throw Error('Module catalog table missing');
    let end = start+2;
    while (tableLines[end]?.startsWith('| ')) end++;
    const groups = new Map([
      ['Controller and graph configuration', []], ['Compute engines', []],
      ['Memory and reset', []], ['Shared arithmetic and LUTs', []],
      ['Legacy core', []], ['Helpers and reference assets', []],
    ]);
    for (const line of tableLines.slice(start+2, end)) {
      const name = line.match(/^\| \[([^\]]+)\]/)?.[1];
      if (!name) throw Error('Unrecognized module row');
      const s = scope.get(name+'.md');
      const group = s === 'Legacy' ? 'Legacy core' : ['Helper','Asset'].includes(s) ? 'Helpers and reference assets' :
        ['llm_soc.sv','llm_pkg.sv'].includes(name) ? 'Controller and graph configuration' :
        /ram|sram|reset/.test(name) ? 'Memory and reset' :
        ['llm_attention_engine.sv','llm_attention_normalize.sv','llm_head_engine.sv','llm_linear_engine.sv','llm_math.sv','ternary_dot32.sv'].includes(name) ? 'Compute engines' : 'Shared arithmetic and LUTs';
      groups.get(group).push(line.replace(/\[(?:View legend|View annotation|View notes|See annotation|View annotation|View notes)\]\(([^)]+)\)/, `[${name} guide]($1)`));
    }
    const replacement = [];
    for (const [title, rows] of groups) if (rows.length) replacement.push('## '+title, '', tableLines[start], tableLines[start+1], ...rows, '');
    tableLines.splice(start, end-start, ...replacement);
    updated = tableLines.join(newline);
  }
  const diagrams = text => [...text.matchAll(/```[\s\S]*?```|!\[[^\]]*\]\([^\n]+\)/g)].map(m => m[0]);
  if (JSON.stringify(diagrams(original)) !== JSON.stringify(diagrams(updated))) throw Error('Diagram/code changed: '+file);
  changes.push(file);
  if (write) fs.writeFileSync(absolute, updated);
}
console.log(JSON.stringify({ mode: write ? 'write' : 'preview', pages: changes.length,
  removedBreadcrumbs, classifiedModuleGuides: scope.size, diagramAndCodeContent: 'unchanged',
  samples: changes.slice(0, 6) }, null, 2));
