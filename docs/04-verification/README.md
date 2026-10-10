# 04 · Verification

[Documentation map](../README.md)

| Topic | Read | Scope |
|---|---|---|
| Verification workflow and gates | [Verification guide](../verification/README.md) | Nine full-graph groups, scoped tests, synthesis and application claims |
| Module testing | [Server test stage](../../tools/server/README.md) | Scoped `--stage test --only TOP` and full regression |
| Test inventory | [Tests index](../../tests/README.md) and [full RTL tests](../../tests/full_rtl/README.md) | Fixtures, assertions and test ownership |
| End-to-end application | [Server application stage](../../tools/server/README.md#application-checkpoint) and [demo flow](../00-start-here/demo-flow.md) | Pretrained checkpoint execution and result interpretation |
| Current evidence/status | [Optimization status](../verification/optimization_status.md) | Which verification and implementation claims match |
| I/O characterization | [I/O cell study](../verification/io_cells/README.md) | Existing characterization scope and evidence |
| Historical reports | [Verification archive](../archive/README.md#verification-and-implementation-snapshots) | Earlier baseline, warning and application snapshots |

The current verification workflow and execution contract own the implemented
gates. Continue with [05 · Implementation](../05-implementation/README.md).
