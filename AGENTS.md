# NPU repository instructions

## 1. Scope

- Work only on the requested/current milestone until implemented and verified, unless blocked by missing information, required approval, or a long-running external job.
- Do not automatically continue into another major milestone.
- Prefer the smallest correct change. Avoid unrelated RTL, architecture, configuration, cleanup, or documentation changes.
- Exception: documentation required to keep modified RTL synchronized is part of the RTL change.
- Treat current repository source, configuration, tests, manifests, and matching generated evidence as the source of truth.
- For server-related tasks, read `tools/server/README.md` for connection, credentials handling, SSH/X11, Slurm, transfer and EDA flow. Do not read the retired `SERVER_ACCESS.md`; credentials are local-only in `tools/server/.local/credentials.json` and must never be printed or committed.

## 2. Context efficiency

Optimize for low context/token use.

- Use `rg` for text/symbols and `rg --files` for files.
- Search before reading large files; read only the smallest relevant region plus required dependencies.
- Batch independent read-only searches when useful.
- Keep output bounded: selected matches, short report sections, log tails, summaries, and scoped diffs.
- Do not recursively dump generated/build directories, large logs, evidence archives, history, or repository-wide diffs.
- Do not reread unchanged files without a concrete reason.
- Prefer dedicated search/patch/Git/file tools over equivalent shell operations.
- `AGENTS.md` is already provided through Codex instruction context; read it from disk only when reviewing/modifying it.
- For large working trees, restrict status/diff inspection to relevant paths.
- Before ending each turn, update `TASK_STATE.md` based on actual task progress. Prefer running an existing monitoring script. If a new script is needed, place it in the scratchpad for one-time jobs; only save reusable scripts permanently.
- Only modify status fields within the relevant sections (e.g., `Timing`, `Simulating`), using exactly `Done` or `In progress`.
- Mark a section as `Done` only when its tasks are fully completed and verified. Otherwise, keep it as `In progress`. Preserve all other content in `TASK_STATE.md` unchanged.

## 3. Repository navigation

- Current full-graph top: `llm_soc`.
- `matmulfree` and its instruction/descriptor datapath are legacy. Inspect/modify them only when explicitly required, affected by shared RTL, or implicated by a required regression.
- For continuation work, read `TASK_STATE.md` once near the beginning for the verified baseline, active issue, and next action.

| Need | Start here |
|---|---|
| RTL graph / ownership | `docs/source_guide/full_graph.md` |
| Architecture / numeric contracts | `docs/design/full_rtl_language.md` |
| Verification / timing status | `docs/verification/optimization_status.md` |
| Verification workflow | `docs/verification/README.md` |
| Language / NanoFable demo | `docs/demos/language.md` |
| RTL policy | `docs/design/rtl_style.md` |

- Do not recursively read `docs/verification/timing/`, `tests/full_rtl/evidence/`, archives/history, or generated build trees.
- Use historical evidence only for a specific comparison, regression, or provenance question.
- For RTL work, prefer actual RTL over generated documentation.
- `llm_soc.sv` is large: locate the relevant symbol/state/instance/parameter before reading source regions.

## 4. RTL ↔ documentation

Documentation synchronization is part of done for RTL changes.

- When synthesizable RTL changes, update its existing `docs/source_guide/blocks/<module>.sv.md` in the same task.
- Keep documentation changes minimal and relevant; RTL remains canonical.
- Do not paste large RTL excerpts or add filler.

Update higher-level docs only when their owned information changes:

| Document | Update when |
|---|---|
| `docs/source_guide/full_graph.md` | hierarchy, ownership, module set, or major block flow changes |
| `docs/design/full_rtl_language.md` | architecture, numeric contracts, memory organization, inference flow, or architectural behavior changes |
| `docs/design/host_interface.md` | host-visible interface/protocol/command semantics change |
| `docs/design/rtl_style.md` | project-wide RTL policy changes |
| `docs/verification/optimization_status.md` | new matching evidence changes verification/timing/resource/application status |

Never invent verification claims.

If an RTL change makes a diagram inaccurate and diagram work is out of scope, record `Diagram follow-up required`.

## 5. Verification

- Current flow on branch `remote`: read `tools/server/README.md`; run Xcelium/Genus only on an approved Linux Slurm compute node with mandatory `--x11`. Use `slurm_x11.sh` from SSH or the account's RDP terminal; never omit `--x11`. Do not run local Quartus/ModelSim/Questa/Verilator entry points.
- Run the smallest directly affected verification first with `tools/server/run_flow.py --stage test --only TOP --tag NEW_TAG`.
- Run all nine full-graph groups (the seven original groups plus linear stream and host cancel) when shared behavior changed or the milestone requires it. Legacy regression uses `--stage legacy` only when implicated.
- Do not rerun expensive regression/timing for unchanged source/configuration when valid matching evidence already exists.
- Synthesis: use `tools/server/run_flow.py --stage syn --lib APPROVED_LIB --tag NEW_TAG`; confirm the lab Genus module and Liberty library first. Preserve prior FPGA evidence; local Quartus timing runner is retired.
- Treat unit/graph, synthesis, fit, timing, portable elaboration, and pretrained-application PASS as separate claims.
- Keep the 100 MHz target explicit in `tools/server/asic.sdc`. Report Genus timing separately from historic FPGA Fmax; flow completion does not establish ASIC physical timing closure.
- Never weaken tests, expected values, timing constraints, or add false/multicycle exceptions to hide failures.
- After a material verified milestone, update `TASK_STATE.md` with only the verified baseline, blocker if any, evidence, and next action. Do not use it as a chronological log.

## 6. Synthesizable RTL

Write deterministic, synthesis-friendly SystemVerilog with explicit hardware structure, timing boundaries, and ownership.

- Prefer explicit RTL when it clarifies replication, pipeline boundaries, register ownership, memory behavior, or control flow.
- Use `generate for` for structural replication/module generation.
- Procedural loops require static bounds and clear resulting hardware; no unbounded/runtime-dependent iteration.
- Avoid synthesizable tasks. Prefer small pure combinational functions or explicit modules.
- Do not hide FSM transitions, register updates, memory transactions, pipeline stages, CDC behavior, or major datapaths inside helpers.
- Every sequential state element must have clear ownership; avoid multiple procedural drivers and unintended latches.
- Preserve externally visible interfaces, protocols, ordering, and verified numerical behavior unless explicitly changed.
- Internal latency/pipeline/register placement may change for timing/area/power if the architectural/protocol contract is preserved or the intended change is verified.
- Prefer clock enables. Do not create gated clocks with ordinary combinational logic.
- Technology-specific clock gating belongs behind an ASIC integration boundary.
- Do not use simulation-only constructs, delays, `force/release`, or unsynthesizable system/file behavior in synthesizable RTL.

## 7. Arithmetic and technology

- Keep functional compute/control RTL technology-independent.
- Isolate technology-specific cells/macros behind wrapper/leaf modules with documented functionality, latency, reset, clocking, and collision behavior.
- `quartus_word_ram` is the only allowed Quartus/Altera memory-IP leaf. Do not add Quartus-specific arithmetic/control IP to portable RTL.
- Isolate ASIC SRAMs, clock-gating cells, and technology cells behind explicit technology/integration boundaries.
- Ordinary synthesizable SystemVerilog operators are allowed when they clearly express intended hardware.
- Preserve NPU arithmetic restrictions: where datapaths intentionally avoid hardware multipliers/dividers, do not replace verified structural logic with runtime `*`, `/`, or vendor arithmetic IP unless explicitly requested and numerical behavior, timing, and area/power impact are verified.
- Constant/elaboration arithmetic is allowed.
- Keep width, signedness, truncation, rounding, saturation, and fixed-point scaling explicit.
- Keep FPGA physical details in the Quartus backend and ASIC physical constraints/libraries/UPF/CTS/DFT/macro binding outside portable compute/control RTL.
- Quartus synthesis/fit/STA is FPGA evidence only, not ASIC synthesis, STA, power, DFT, CDC/RDC, physical-design, or signoff evidence.

## 8. Workspace and Git safety

- Preserve user changes, valid uncommitted work, and verification evidence.
- Do not reset, revert, delete, overwrite, clean, or discard existing work unless explicitly required.
- Do not use destructive Git commands merely to simplify the workspace.
- Before editing a file with uncommitted changes, inspect its relevant diff.
- Do not modify source/configuration while an active Quartus run is measuring it.
- Do not commit or push unless explicitly requested.
- At RTL task completion, confirm intended RTL changed, required documentation changed, and unrelated files did not.

## 9. Long-running jobs

For Quartus synthesis/fit/STA, long simulations, or similar jobs:

- Start normally and capture identifying information.
- Perform at most one initial status check. If still running, do not repeatedly poll or keep the turn active waiting.
- Record continuation state in `TASK_STATE.md`, then hand monitoring to the user.
- The handoff must provide: job/stage, PID/process if available, exact log/report path, one bounded process check, one bounded progress/log-tail command, completion marker, expected output/report, and when to continue.
- On continuation, inspect final status/report once, verify source/configuration/evidence provenance, and resume from `TASK_STATE.md`.
- Do not relaunch a running/completed job merely because the previous Codex turn ended; relaunch only if evidence is invalid or source/configuration changed.
- Short jobs completing within the current tool call need no handoff.
- Before ending each turn, run an existing monitoring script or edit it in scratchpad section if those jobs will not be reused in the future to automatically update `TASK_STATE.md` based on actual task progress.
- Only update the status within the relevant sections (e.g., `Timing`, `Simulating`), using exactly `Done` or `In progress`.
- Mark a section as `Done` only when its tasks are fully completed and verified. Do not modify any other content in `TASK_STATE.md`.

## 10. Documentation diagrams

When creating or materially editing Mermaid diagrams under `docs/`:

- Read and follow `docs/diagrams/diagram_style.md`.
- Treat diagrams as architecture documentation, not RTL schematics.
- Optimize for normal Markdown-width readability and reuse project conventions.
- Split complex modules into overview/datapath/control diagrams when useful.
- Do not restyle existing diagrams unless documentation cleanup is the task.
- Read the original `.drawio` only if `diagram_style.md` is insufficient or explicit comparison is required.
