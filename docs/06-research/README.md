# 06 · Research

[Documentation map](../README.md)

Research pages explain why an optimization was proposed and what trade-offs were
expected. They are not automatically descriptions of current RTL. The execution
contract says which phase is implemented; the verification status says which
measured evidence matches it.

| Topic | Read | Scope |
|---|---|---|
| Optimization rationale | [Exact throughput optimization](../design/exact_throughput_optimization.md) | Cache, streaming and resource-ownership proposals |
| Implemented milestones | [Execution contract](../NPU_V2_EXECUTION.md) | Phases, constraints and measurement gates |
| Measured comparisons | [Verification status](../verification/optimization_status.md) | Matching throughput, timing and resource evidence |
| Implementation reviews | [Decisions/reviews](../decisions/README.md) | Rationale tied to named source snapshots |
| Previous architecture research | [Research snapshot](../history/architecture_research_20261005.md) and [baseline study](../verification/npu100_b1_baseline/ARCH_RESEARCH.md) | Historical architectural comparisons |
| Research/reference inventory | [History index](../history/README.md#thesis-poster-slide-và-bài-báo) | Thesis, poster, slides and paper references |

The repository's measured comparisons are the benchmark entry point. A review,
proposal or historical estimate is not a new verified performance result.

## Separate hypothesis from conclusion

For each optimization, identify the bottleneck being targeted, the mechanism
that should improve it, behavior that must remain unchanged, and the evidence
required to accept the change. Compare cycles only for equivalent transactions
and compare timing/resources only for matching constraints and backends. A lower
cycle count can still be a regression if numeric results, ordering, cancellation,
or clock frequency no longer meet their contracts.
