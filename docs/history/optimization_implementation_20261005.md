# Optimization implementation history

The workspace cleanup on 2026-10-05 preserves the one-shot optimization scripts
and superseded staging sources in `optimization_implementation_20261005.zip`,
with their original `tools/...` paths. Each ZIP entry was checked against the
original file's SHA-256 before the live helper files were removed.

These files describe intermediate transformations. They are not a replay
interface: later verified corrections exist in the active RTL and may be
overwritten by those transformations. Current RTL remains in
`Verilog Source code`; standard runners are listed in
`docs/verification/optimization_status.md`.

`tools/optimization/checkpoint.py` remains available for fresh checkpoint
archiving and task-specific code counts. All original verification evidence
and task-start snapshots retain their original paths and bytes.

The cleanup manifest, `workspace_cleanup_20261005.json`, records removed cache
paths, sizes, archived helper hashes and the protected-file verification.
`workspace_cleanup_20261005.ps1` records the cleanup procedure and refuses to
overwrite its history or execute while EDA processes are active.
