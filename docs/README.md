# Documentation Index

Navigation map for the incremental parser. Start here, go one level deeper for detail.

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

## Architecture Decisions (ADRs)

- [decisions/2026-02-27-remove-tokenStage-memo.md](decisions/2026-02-27-remove-tokenStage-memo.md)
- [decisions/2026-02-28-edit-lengths-not-endpoints.md](decisions/2026-02-28-edit-lengths-not-endpoints.md)

## Active Plans (Future Work)

- [plans/2026-02-25-node-interner-design.md](plans/2026-02-25-node-interner-design.md)
- [plans/2026-02-25-node-interner.md](plans/2026-02-25-node-interner.md)
- [plans/2026-02-25-syntax-node-extend.md](plans/2026-02-25-syntax-node-extend.md)
- [plans/2026-02-25-syntax-node-first-layer-design.md](plans/2026-02-25-syntax-node-first-layer-design.md)

## Archive (Historical / Completed)

- [archive/completed-phases/phases-0-4.md](archive/completed-phases/phases-0-4.md) — Phases 0–4 full implementation notes
- [archive/completed-phases/](archive/completed-phases/) — all completed phase plan files (15 files)
- [archive/LEZER_IMPLEMENTATION.md](archive/LEZER_IMPLEMENTATION.md) — Lezer study notes
- [archive/LEZER_FRAGMENT_REUSE.md](archive/LEZER_FRAGMENT_REUSE.md) — fragment reuse research
- [archive/green-tree-extraction.md](archive/green-tree-extraction.md)
- [archive/IMPLEMENTATION_SUMMARY.md](archive/IMPLEMENTATION_SUMMARY.md)
- [archive/IMPLEMENTATION_COMPLETE.md](archive/IMPLEMENTATION_COMPLETE.md)
- [archive/COMPLETION_SUMMARY.md](archive/COMPLETION_SUMMARY.md)
- [archive/TODO_ARCHIVE.md](archive/TODO_ARCHIVE.md)
