# NPU repository instructions

## 1. Working policy

Work only on the requested or currently active milestone.

Continue until that milestone is implemented and verified unless blocked by:

- missing information;
- required user approval;
- an external tool or long-running process.

Do not automatically continue into another major milestone after the active milestone is complete.

Prefer the smallest correct change.

Avoid unrelated:

- RTL refactors;
- architecture changes;
- configuration changes;
- cleanup;
- documentation changes.

**Exception:** documentation required to keep modified RTL synchronized is part of the RTL change and is mandatory.

Treat the current repository, configuration, tests, manifests, source code, and generated reports as the source of truth.

For large JSON manifests, reports, logs, or result files, inspect only the fields or sections needed for the current decision.

---

# 2. Efficient search and context use

Optimize repository work for low context/token usage.

When searching:

- use `rg` for text and symbols;
- use `rg --files` for files;
- search before reading large files;
- read the smallest useful source region plus required dependencies;
- batch independent read-only searches when practical.

Keep command output bounded.

Prefer:

- selected matches;
- short report sections;
- summaries;
- log tails;
- scoped diffs;

instead of full file or directory dumps.

Do not recursively dump:

- generated build directories;
- large logs;
- evidence archives;
- repository-wide diffs;
- history/archive trees.

Do not reread unchanged files without a concrete reason.

Use dedicated search, patch, Git, or file tools when available instead of recreating the same operation with general shell commands.

`AGENTS.md` is already supplied through Codex instruction context.

Do not read it from disk unless the active task is specifically reviewing or modifying `AGENTS.md`.

For a large Git working tree, inspect counts first and then restrict status/diff inspection to paths relevant to the active task.

---

# 3. Repository navigation

The current full-graph top is:

`llm_soc`

`matmulfree` and its instruction/descriptor datapath are legacy.

Do not inspect or modify legacy RTL unless:

- the active task explicitly concerns it;
- a modified shared module affects it;
- a required regression reports a failure there.

For continuation work, read `TASK_STATE.md` once near the beginning to recover:

- the verified baseline;
- the active issue;
- the expected next action.

Use these documentation entry points:

| Need | Start here |
|---|---|
| Current RTL graph / module ownership | `docs/source_guide/full_graph.md` |
| Current architecture / numeric contracts | `docs/design/full_rtl_language.md` |
| Current verification / timing status | `docs/verification/optimization_status.md` |
| Verification workflow | `docs/verification/README.md` |
| Language / NanoFable demo | `docs/demos/language.md` |
| RTL coding policy | `docs/design/rtl_style.md` |

Do not recursively read:

- `docs/verification/timing/`;
- `tests/full_rtl/evidence/`;
- history/archive directories;
- generated build directories.

Open historical evidence only for a specific:

- comparison;
- regression;
- provenance question.

For RTL coding work, prefer the actual RTL source over generated/source-guide explanations.

Read the module documentation when:

- architecture context is needed;
- documentation itself is being changed;
- or the RTL has been modified and its documentation must be synchronized.

`llm_soc.sv` is large.

Search for the relevant:

- state;
- signal;
- instance;
- parameter;
- module;
- symbol;

before reading source regions.

Do not read the entire file merely to locate a local issue.

---

# 4. RTL ↔ documentation synchronization

Documentation synchronization is part of the definition of done for RTL changes.

## Per-module requirement

Whenever a synthesizable RTL file is modified, the corresponding module documentation must also be updated in the same task.

For example:

```text
llm_soc.sv
→ docs/source_guide/blocks/llm_soc.sv.md

llm_attention_engine.sv
→ docs/source_guide/blocks/llm_attention_engine.sv.md
```

If a corresponding module documentation page exists, it MUST be edited when the RTL file changes.

Do not mark an RTL task complete while its module documentation still describes the previous implementation.

If the RTL change does not alter externally visible semantics, update only the smallest relevant documentation content, such as:

- implementation description;
- state/datapath explanation;
- ownership information;
- source-sync/hash metadata when present;
- implementation notes relevant to the changed logic.

Do not add meaningless prose merely to create a documentation diff.

## Propagation rule

Update higher-level documentation only when the RTL change affects the information owned by that document.

### Update `docs/source_guide/full_graph.md` when:

- module hierarchy changes;
- block ownership changes;
- a module is added or removed;
- data/control flow between major blocks changes.

### Update `docs/design/full_rtl_language.md` when:

- graph architecture changes;
- model dimensions or numeric contracts change;
- memory organization changes;
- major inference flow changes;
- architectural behavior changes.

### Update `docs/design/host_interface.md` when:

- host-visible interface behavior changes;
- protocol behavior changes;
- command/result semantics change.

### Update `docs/design/rtl_style.md` only when:

- the project-wide RTL policy itself changes.

Do not update it merely because RTL was modified.

### Update `docs/verification/optimization_status.md` only when:

- new verification evidence has actually been produced;
- current PASS/FAIL status changes;
- timing/resource/application evidence changes.

Never invent or copy current verification claims without matching evidence.

## Documentation style for RTL changes

Do not paste large RTL excerpts into documentation.

The RTL source is the canonical source code.

Documentation should explain:

- role;
- ownership;
- flow;
- important state/datapath groups;
- interfaces/contracts;
- non-obvious behavior.

Prefer concise tables, bullets, and links over duplicated source.

If an RTL change makes an existing diagram inaccurate and diagram work is outside the current task, record:

`Diagram follow-up required`

rather than silently leaving the inconsistency unnoticed.

---

# 5. Verification workflow

Run the smallest directly affected verification first.

For full-graph debugging, use the targeted `run_units.ps1` group when possible.

Run the complete seven-group regression when:

- shared behavior changed;
- the milestone requires full regression evidence;
- the pretrained-application gate requires it.

Do not rerun expensive regression or timing solely to reconfirm unchanged source/configuration when valid matching evidence already exists.

For full-top timing, use:

`tools/timing/run.ps1`

with:

`quartus/llm_soc`

and a fresh evidence tag.

Preserve previous evidence tags and reports.

Treat these as separate claims:

- unit/graph PASS;
- synthesis PASS;
- fit PASS;
- timing PASS;
- portable elaboration PASS;
- pretrained application PASS.

For the 100 MHz timing target, a timing failure does not by itself require stopping optimization work.

Reporting the resulting Fmax is sufficient unless the active milestone explicitly requires timing closure.

Never weaken:

- tests;
- expected values;
- timing constraints;

and never introduce false/multicycle exceptions merely to hide a real failure.

After a material verified milestone, update `TASK_STATE.md` concisely with:

- verified baseline;
- remaining blocker, if any;
- relevant evidence;
- next action.

Do not use `TASK_STATE.md` as a chronological work log.

---

# 6. Synthesizable RTL policy

Write deterministic, synthesis-friendly SystemVerilog.

Keep hardware structure, timing boundaries, and ownership explicit.

Prefer explicit RTL when it makes:

- hardware replication;
- pipeline boundaries;
- register ownership;
- memory behavior;
- control flow;

easier to understand.

Use `generate for` for structural hardware replication and module/interface generation.

Procedural loops are allowed when:

- bounds are statically determinable;
- the resulting hardware remains clear;
- they do not unintentionally create excessive replication or long combinational paths.

Do not use:

- unbounded loops;
- loops whose hardware iteration count depends on runtime data.

Avoid synthesizable tasks.

For code reuse, prefer:

- small pure combinational functions;
- explicit modules.

Functions may be used for:

- small pure combinational transformations;
- constant/elaboration helpers.

Do not hide inside helpers:

- FSM transitions;
- register updates;
- memory transactions;
- pipeline stages;
- clock-domain behavior;
- significant datapaths.

Each sequential state element must have clear ownership.

Avoid:

- multiple procedural drivers;
- unintended latches.

Preserve externally visible:

- interfaces;
- protocols;
- ordering;
- verified numerical behavior;

unless the active task explicitly changes them.

Internal:

- latency;
- pipeline structure;
- register placement;

may change for timing, area, or power optimization when the architectural/protocol contract remains preserved or the intended contract change is explicitly verified.

Prefer clock enables in portable RTL.

Do not create gated clocks using ordinary combinational logic.

Technology-specific clock gating belongs behind an ASIC technology/integration boundary.

Do not use simulation-only constructs, delays, force/release, or unsynthesizable system/file behavior in synthesizable RTL.

---

# 7. Arithmetic and technology policy

Keep functional compute/control RTL technology-independent.

Technology-specific cells or macros must be isolated behind clearly defined wrapper or leaf modules.

Their contracts must document relevant:

- functionality;
- latency;
- reset behavior;
- clocking;
- collision behavior.

For the current Quartus backend:

`quartus_word_ram`

is the only allowed Quartus/Altera memory-IP leaf.

Do not introduce Quartus-specific arithmetic or control IP into portable compute/control RTL.

Future ASIC-specific components such as:

- SRAM macros;
- clock-gating cells;
- technology cells;

must be isolated behind dedicated technology wrappers or implementation/integration layers.

Portable-facing behavior must remain explicit.

Use ordinary synthesizable SystemVerilog operators when they clearly express the intended hardware.

Do not prohibit an operator merely because it can infer arithmetic hardware.

However, preserve architecture-specific arithmetic restrictions.

For NPU datapaths intentionally designed to avoid hardware multipliers/dividers, do not replace verified structural implementations with runtime:

- `*`;
- `/`;
- vendor arithmetic IP;

unless the active task explicitly changes that policy and verifies:

- numerical behavior;
- timing;
- area/power implications.

Constant multiplication, division, indexing, and geometry used only for elaboration are allowed.

Make these explicit enough for hardware review:

- width;
- signedness;
- truncation;
- rounding;
- saturation;
- fixed-point scaling.

Keep FPGA-specific:

- placement;
- routing;
- I/O;
- pin assignments;
- delay chains;
- physical optimization assignments;

inside the Quartus backend rather than portable RTL.

Keep ASIC-specific:

- physical constraints;
- library bindings;
- UPF/power intent;
- CTS;
- DFT;
- technology macro binding;

outside portable compute/control RTL except at explicit integration boundaries.

Quartus synthesis, fit, and STA are FPGA implementation evidence only.

They do not constitute ASIC:

- synthesis;
- STA;
- power;
- DFT;
- CDC/RDC;
- physical design;
- signoff evidence.

---

# 8. Workspace and Git safety

Preserve:

- user changes;
- valid uncommitted work;
- immutable verification evidence.

Do not:

- reset;
- revert;
- delete;
- overwrite;
- clean;
- discard existing work;

unless the active task explicitly requires it.

Do not use destructive Git commands merely to simplify the workspace.

Before modifying a file that already has uncommitted changes, inspect its relevant diff first.

Do not modify source/configuration while an active Quartus run is measuring that source/configuration.

Do not commit or push unless explicitly requested.

At the end of an RTL task, verify that:

- intended RTL files changed;
- corresponding module documentation changed;
- required higher-level documentation changed;
- unrelated files did not change.

---

# 9. Long-running jobs

For simulations, regressions, synthesis, fit, timing analysis, or other long-running processes:

1. start the job normally;
2. capture enough information to identify it;
3. perform at most one initial status check;
4. if it is still running, do not repeatedly poll it.

Do not repeatedly inspect:

- process status;
- logs;
- intermediate output files.

Do not relaunch an existing job merely because a previous Codex turn stopped.

When a job must continue outside the current turn:

- record required continuation state in `TASK_STATE.md`;
- provide a concise **monitor handoff**.

The handoff must include:

- running job/stage;
- PID/process name when available;
- relevant log/report path;
- one bounded command to check whether it is running;
- one bounded command to inspect recent progress;
- completion/success/failure marker;
- expected output/report;
- instruction to continue the existing Codex task after completion.

Prefer small monitoring outputs such as:

- process queries;
- short log tails.

When continuing after the job completes:

1. inspect final status/results once;
2. confirm they correspond to the expected source/configuration/evidence tag;
3. continue from `TASK_STATE.md`;
4. do not relaunch the job unless the result is invalid or source/configuration changed.

Short jobs that complete within the current tool call do not require this handoff.