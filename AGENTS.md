# NPU repository instructions

## General working policy

Work only on the requested or currently active milestone.

Continue working until that milestone is implemented and verified, unless blocked by missing information, required user approval, or an external tool/process.

Do not automatically continue into another major milestone after the requested one is complete.

Prefer the smallest correct change. Avoid unrelated refactors, cleanup, documentation updates, or architectural changes.

Treat the current repository, configuration, tests, manifests, and generated reports as the source of truth.

## Search and tool use

When searching for text or symbols, prefer `rg`. When searching for files, prefer `rg --files`.

Use a dedicated file, search, patch, or Git tool when one is available instead of reproducing the same operation through a more general shell command.

Search before reading large files.

Inspect the smallest useful file region plus the dependencies required to understand or modify it.

Batch independent read-only searches and checks when practical.

Keep command output bounded. Prefer summaries, selected matches, relevant report sections, and log tails over full dumps.

Do not recursively dump large directories, generated outputs, build logs, evidence archives, or repository-wide diffs into context.

Do not repeatedly poll long-running simulations or Quartus processes. Check them when the result is needed for the next decision.

AGENTS.md is already supplied through the Codex instruction context. Do not read it from disk unless the active task is to review or edit AGENTS.md itself.

If global git status is large, summarize its counts and inspect only dirty paths relevant to the active task instead of dumping the full status into context.

## Repository navigation

The current full-graph top is `llm_soc`.

`matmulfree` and its instruction/descriptor datapath are legacy. Do not inspect or modify legacy RTL unless:
- the active task explicitly concerns it;
- a changed shared module affects it; or
- a required regression identifies a failure there.

For continuation work, read `TASK_STATE.md` once near the beginning to recover the verified state and active issue.

For architecture questions, start with `docs/source_guide/full_graph.md`.

For verification or timing work, start with `docs/verification/optimization_status.md` and then inspect only the relevant current manifest, report, or log.

Use `docs/design/full_rtl_language.md` when graph architecture or numeric contracts are relevant.

Do not recursively read:
- `docs/verification/timing/`
- `tests/full_rtl/evidence/`
- history/archive directories
- generated build directories

Open historical evidence only for a specific comparison, regression, or provenance question.

Do not read a generated/source-guide block explanation when the corresponding RTL source already provides everything needed for the active coding task. Use those pages when documentation, architecture explanation, or a saved snapshot is specifically relevant.

`llm_soc.sv` is large. Search for the relevant state, signal, instance, or symbol before reading it. Do not read the whole file merely to locate a local issue.

Do not reread unchanged files without a concrete reason.

## Verification workflow

Run the smallest directly affected verification first.

While debugging a full-graph problem, use the targeted `run_units.ps1` group when possible.

Run the complete seven-group regression when:
- shared behavior changed;
- a milestone requires full regression evidence; or
- the pretrained-application gate requires it.

Do not rerun expensive regression or timing merely to reconfirm unchanged source/configuration when valid matching evidence already exists.

For full-top timing, use `tools/timing/run.ps1` with `quartus/llm_soc` and a fresh evidence tag.

Preserve previous evidence tags and reports.

Treat unit/graph PASS, synthesis PASS, fit PASS, timing PASS, portable elaboration PASS, and pretrained application PASS as separate claims.

Before pretrained application execution, require exact-current unit/graph PASS and exact-current full-top post-fit timing >=100 MHz at every required corner, with:
- nonnegative setup slack;
- nonnegative hold slack;
- nonnegative recovery/removal slack;
- nonnegative pulse-width slack;
- TNS = 0;
- no unconstrained paths.

Never weaken tests, expected values, timing constraints, or introduce false/multicycle exceptions merely to hide a real failure.

After a material verified milestone, update `TASK_STATE.md` concisely with:
- the verified baseline;
- the remaining blocker, if any;
- the relevant evidence;
- the next action.

Do not use `TASK_STATE.md` as a chronological work log.

## Synthesizable RTL

Write deterministic, synthesis-friendly SystemVerilog with hardware structure and ownership kept clear.

Prefer explicit RTL when it makes the intended hardware, pipeline boundaries, or register ownership easier to understand.

Use generate for for structural hardware replication and module/interface generation.

Procedural loops are allowed when their bounds are statically determinable at elaboration/synthesis time and the resulting hardware remains clear. Avoid large procedural loops that unintentionally create long combinational paths or excessive replicated hardware.

Do not use unbounded loops or loops whose hardware iteration count depends on runtime data.

Avoid synthesizable task. If code reuse is needed, prefer a small pure combinational function or an explicit module. Do not use tasks/functions to hide state, timing, handshakes, memory transactions, or significant datapaths.

Functions may be used for small pure combinational transformations and constant/elaboration helpers.

Do not hide FSM transitions, register updates, memory accesses, pipeline stages, clock-domain behavior, or significant datapaths inside helper abstractions.

Each sequential state element should have clear ownership. Avoid multiple procedural drivers and unintended latches.

Preserve externally visible interfaces, protocols, ordering, and verified numerical behavior unless the active task explicitly changes them.

Internal latency, pipeline structure, and register placement may change when required for timing, area, or power optimization, provided the architectural/protocol contract is preserved or the intended contract change is explicitly verified.

Prefer clock enables in portable RTL. Do not create gated clocks with ordinary combinational logic. Technology-specific clock-gating implementation belongs behind the ASIC technology/integration boundary.

Do not rely on simulation-only constructs, delays, force/release, or unsynthesizable file/system-task behavior in synthesizable RTL.

## Arithmetic and technology policy

Keep functional compute/control RTL technology-independent.

Technology-specific macros or cells must be isolated behind clearly defined wrapper or leaf modules with documented functional, latency, reset, clocking, and collision behavior.

For the current Quartus backend, quartus_word_ram is the only allowed Quartus/Altera memory-IP leaf. Do not introduce Quartus-specific arithmetic or control IP into portable compute/control RTL.

For a future ASIC backend, SRAM macros, clock-gating cells, or other required technology cells may be introduced only through dedicated technology wrappers or implementation/integration layers. Their portable-facing contracts must remain explicit.

Use ordinary synthesizable SystemVerilog operators when they express the intended hardware clearly. Do not prohibit an operator solely because it can infer arithmetic hardware.

However, preserve architecture-specific arithmetic restrictions where they are intentional. In NPU datapaths designed to avoid hardware multipliers/dividers, do not replace the verified structural implementation with runtime *, /, or vendor arithmetic IP unless the active task explicitly changes that architectural policy and verifies PPA, timing, and numerical behavior.

Constant multiplication, division, indexing, and geometry used only for elaboration are permitted.

Do not infer expensive arithmetic accidentally. Width, signedness, truncation, rounding, saturation, and fixed-point scaling must be explicit enough to make the intended hardware and numerical behavior reviewable.

Keep FPGA-specific placement, routing, I/O, pin, delay-chain, and physical optimization assignments in the Quartus backend rather than portable RTL.

Keep ASIC-specific physical constraints, library bindings, UPF/power intent, CTS/DFT implementation details, and technology macro bindings outside the portable compute/control RTL except at explicit integration boundaries.

Quartus synthesis, fit, and STA are FPGA implementation evidence only. They do not constitute ASIC synthesis, STA, power, DFT, CDC/RDC, physical-design, or signoff evidence.

## Workspace and Git safety

Preserve user changes, correct uncommitted work, and immutable verification evidence.

Do not reset, revert, delete, overwrite, clean, or discard existing work unless the active task explicitly requires that action.

Do not use destructive Git commands to simplify the workspace.

Inspect the relevant diff before changing code that already has uncommitted modifications.

Do not modify source or configuration while an active Quartus run is measuring that source/configuration.

Do not commit or push unless the active task explicitly asks for it.