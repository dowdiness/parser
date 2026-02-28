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

- [plans/2026-02-28-move-tokenbuffer-to-core.md](plans/2026-02-28-move-tokenbuffer-to-core.md) — move TokenBuffer[T] + LexError to @core for multi-language foundation
- [plans/2026-02-28-consolidate-lambda-v3.md](plans/2026-02-28-consolidate-lambda-v3.md) — consolidate lambda package + generic IncrementalParser
- [plans/2026-02-28-text-delta.md](plans/2026-02-28-text-delta.md) — implementation plan for TextDelta → Edit adapter

## Archive (Historical / Completed)

- [archive/completed-phases/2026-02-28-generic-token-buffer.md](archive/completed-phases/2026-02-28-generic-token-buffer.md) — generify TokenBuffer[T] + re-export @token.TokenInfo via pub using
- [archive/completed-phases/2026-02-28-text-delta-design.md](archive/completed-phases/2026-02-28-text-delta-design.md) — TextDelta → Edit adapter design
- [archive/completed-phases/2026-02-28-grammar-expansion-let.md](archive/completed-phases/2026-02-28-grammar-expansion-let.md) — expression-level `let` binding implementation
- [archive/completed-phases/2026-02-28-incremental-parser-cleanup-design.md](archive/completed-phases/2026-02-28-incremental-parser-cleanup-design.md) — IncrementalParser holdover cleanup design
- [archive/completed-phases/2026-02-28-incremental-parser-cleanup.md](archive/completed-phases/2026-02-28-incremental-parser-cleanup.md) — IncrementalParser holdover cleanup implementation plan
- [archive/completed-phases/](archive/completed-phases/) — all completed phase plans (Phases 0–7, SyntaxNode-first layer, NodeInterner, docs reorganization, dead-code audit)
- [archive/](archive/) — research notes (Lezer, fragment reuse) and historical status docs
