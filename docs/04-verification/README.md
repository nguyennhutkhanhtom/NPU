# 04 · Verification

[Documentation map](../README.md)

Verification is layered because no single run proves everything. A unit test can
locate an arithmetic or protocol bug quickly; an integrated graph regression
checks interaction; an application run checks a real fixture; synthesis and
timing answer implementation questions. Each result must name its own scope.

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

## How to interpret PASS

`PASS` means all assertions in that named test or stage succeeded for its exact
inputs. It does not mean untested inputs are correct, and it does not transfer to
changed source. Prefer statements such as “the nine full-graph groups pass for
manifest X” over “the NPU is fully verified.” Warnings must be reviewed in
context; zero errors alone is not enough when the expected completion marker is
missing.
