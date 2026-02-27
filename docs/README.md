# Documentation Index

Navigation map for the incremental parser. Start here, go one level deeper for detail.

> **Maintenance rules:** (1) Update this file in the same commit as any `.md` add/move/remove.
> (2) When a plan is complete: add `**Status:** Complete` to the file, then `git mv` to `archive/completed-phases/`.
> (3) Keep `README.md` ≤60 lines and `ROADMAP.md` ≤450 lines — extract details into sub-docs.

## Architecture

Understanding how the layers fit together:

- [architecture/overview.md](architecture/overview.md) — layer diagram, architectural principles
- [architecture/pipeline.md](architecture/pipeline.md) — parse pipeline step by step
- [architecture/language.md](architecture/language.md) — grammar, syntax, Token/Term data types
- [architecture/seam-model.md](architecture/seam-model.md) — `CstNode`/`SyntaxNode` two-tree model
- [architecture/generic-parser.md](architecture/generic-parser.md) — `LanguageSpec`, `ParserContext` API

## API Reference

- [api/reference.md](api/reference.md) — all public functions, error types, usage examples
- [api/api-contract.md](api/api-contract.md) — API contract and stability guarantees
- [api/pipeline-api-contract.md](api/pipeline-api-contract.md) — pipeline API contract

## Correctness

- [correctness/CORRECTNESS.md](correctness/CORRECTNESS.md) — correctness goals and verification
- [correctness/STRUCTURAL_VALIDATION.md](correctness/STRUCTURAL_VALIDATION.md) — structural validation details
- [correctness/EDGE_CASE_TESTS.md](correctness/EDGE_CASE_TESTS.md) — edge-case test catalog

## Performance

- [performance/PERFORMANCE_ANALYSIS.md](performance/PERFORMANCE_ANALYSIS.md) — benchmarks and analysis
- [performance/benchmark_history.md](performance/benchmark_history.md) — historical benchmark log
- [../BENCHMARKS.md](../BENCHMARKS.md) — benchmark results and raw data (root-level)

## Architecture Decisions (ADRs)

- [decisions/2026-02-27-remove-tokenStage-memo.md](decisions/2026-02-27-remove-tokenStage-memo.md)
- [decisions/2026-02-28-edit-lengths-not-endpoints.md](decisions/2026-02-28-edit-lengths-not-endpoints.md)

## Active Plans (Future Work)

- [plans/2026-02-28-dead-code-audit-design.md](plans/2026-02-28-dead-code-audit-design.md) — remove `src/crdt/`, fix stale docs, complete package map

## Archive (Historical / Completed)

**Completed phase plans:**
- [archive/completed-phases/phases-0-4.md](archive/completed-phases/phases-0-4.md) — Phases 0–4 consolidated notes
- [archive/completed-phases/](archive/completed-phases/) — all 18 individual completed phase plan files
- [archive/completed-phases/2026-02-25-syntax-node-extend.md](archive/completed-phases/2026-02-25-syntax-node-extend.md) — SyntaxNode API extension plan
- [archive/completed-phases/2026-02-25-syntax-node-first-layer-design.md](archive/completed-phases/2026-02-25-syntax-node-first-layer-design.md) — SyntaxNode-first layer design
- [archive/completed-phases/2026-02-28-docs-hierarchy-reorganization.md](archive/completed-phases/2026-02-28-docs-hierarchy-reorganization.md) — docs reorganization plan
- [archive/completed-phases/2026-02-25-node-interner-design.md](archive/completed-phases/2026-02-25-node-interner-design.md) — NodeInterner design
- [archive/completed-phases/2026-02-25-node-interner.md](archive/completed-phases/2026-02-25-node-interner.md) — NodeInterner implementation plan

**Research notes:**
- [archive/LEZER_IMPLEMENTATION.md](archive/LEZER_IMPLEMENTATION.md) — Lezer study notes
- [archive/LEZER_FRAGMENT_REUSE.md](archive/LEZER_FRAGMENT_REUSE.md) — fragment reuse research
- [archive/lezer.md](archive/lezer.md) — original Lezer research notes (pre-reorganization)
- [archive/green-tree-extraction.md](archive/green-tree-extraction.md) — early extraction task notes (see also `completed-phases/2026-02-19-green-tree-extraction.md` for full plan)

**Historical status docs:**
- [archive/TODO.md](archive/TODO.md) — completed-task log (Phases 1–7)
- [archive/IMPLEMENTATION_SUMMARY.md](archive/IMPLEMENTATION_SUMMARY.md)
- [archive/IMPLEMENTATION_COMPLETE.md](archive/IMPLEMENTATION_COMPLETE.md)
- [archive/COMPLETION_SUMMARY.md](archive/COMPLETION_SUMMARY.md)
- [archive/TODO_ARCHIVE.md](archive/TODO_ARCHIVE.md)
