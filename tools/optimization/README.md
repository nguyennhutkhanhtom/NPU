# Optimization evidence helper

> **Category: GUIDE.**

This helper records and compares artifacts; it does not turn an estimate into a
verified result. Read [the evidence levels](../../docs/00-start-here/fundamentals.md#from-rtl-to-evidence)
and compare only snapshots with matching source, configuration, and constraints.

Run commands from the repository root:

```powershell
python tools/optimization/checkpoint.py
python tools/optimization/checkpoint.py --archive FRESH_TAG
```

The first command reports RTL code changes against the preserved task-start
baseline. The second creates a new immutable checkpoint from current RTL,
tests and unit-result logs; existing tags must not be overwritten.

Historical one-shot RTL transformations and staging files are retained in
`docs/history/optimization_implementation_20261005.zip` and must not be replayed
against the completed design. Use the standard runners in
[verification status](../../docs/verification/optimization_status.md).
