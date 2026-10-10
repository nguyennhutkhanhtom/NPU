# Source Guide

<!-- reading-navigation:start -->
[Documentation](../README.md) → [02 · Architecture](../02-architecture/README.md) → This page

| Reading guide | Document |
|---|---|
| New to the subject | [NPU and RTL fundamentals](../00-start-here/fundamentals.md) · [Glossary](../00-start-here/glossary.md) |
| Read first | [System architecture](../design/full_rtl_language.md) |
| Continue / related lookup | [Module catalog](blocks/README.md) |
<!-- reading-navigation:end -->

> **Category: GUIDE.** Navigate the current RTL without loading source listing copies.

The guide is organized by ownership rather than source-file size. Each module
page first states what the block owns, then its timing/protocol contract, major
state groups, and related blocks. Read [the fundamentals](../00-start-here/fundamentals.md)
if you need an introduction to registers, combinational logic, FSMs, pipelines,
handshakes, memory latency, or fixed-point notation.

| Start from | Purpose |
|---|---|
| [Full graph](full_graph.md) | Current top `llm_soc`, module responsibilities, and shared resources |
| [Module index](blocks/README.md) | Source links and brief notes for each block |
| [Current architecture](../design/full_rtl_language.md) | Model geometry, inference flow, and numeric contract |
| [Hierarchy legacy](legacy/README.md) | Core instruction/descriptor `matmulfree` |
| [Diagram index](../diagrams/README.md) | Existing hierarchy and diagram assets |

RTL is the reference source for implementation details. Find the necessary state/signal
before reading a large module. The current verification and implementation status:
[optimization status](../verification/optimization_status.md).
