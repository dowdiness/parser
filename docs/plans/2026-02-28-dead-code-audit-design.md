# Design: Dead Code Audit — Remove `src/crdt/` and Fix Documentation

**Created:** 2026-02-28
**Status:** Approved

## Problem

Three coordinated issues make the codebase harder to understand than it needs to be:

1. **`src/crdt/` is conceptual dead weight.** The package contains `CRDTNode`, `ParsedDocument`,
   `ast_to_crdt`, and `crdt_to_source` — explicitly described in the ROADMAP as "Research phase /
   conversion functions only; no conflict logic." It has no callers in the parent `dowdiness/crdt`
   repo (verified by grep), appears in the public API facade (`src/lib.mbt` and
   `src/pkg.generated.mbti`), and is benchmarked in `src/benchmarks/` — making it look like
   load-bearing infrastructure when it isn't.

2. **`src/lib.mbt` has stale package references.** The comment block lists
   `dowdiness/parser/range` and `dowdiness/parser/edit` as separate packages (both merged into
   `src/core/` in Phase 6), and attributes `CstNode` to `src/syntax/` instead of `seam/`.

3. **CLAUDE.md package map is incomplete.** `src/token/`, `src/syntax/`, and `src/benchmarks/`
   are active packages not listed in the map, making them invisible to developers and AI agents.

## Verification

Confirmed zero live-code references to `CRDTNode`, `ParsedDocument`, `ast_to_crdt`,
`crdt_to_source` outside of `parser/` itself:

```
grep -r "ast_to_crdt|crdt_to_source|CRDTNode|ParsedDocument|parser/crdt" \
  /home/.../crdt --exclude-dir=parser --exclude-dir=_build
# → only hits in docs/archive/ (historical planning notes)
```

## Changes

### 1. Delete `src/crdt/`

- Remove `src/crdt/crdt_integration.mbt`
- Remove `src/crdt/crdt_integration_test.mbt`
- Remove `src/crdt/moon.pkg`

### 2. Update `src/moon.pkg`

Remove `"dowdiness/parser/crdt"` from the import list.

### 3. Update `src/lib.mbt`

- Remove the two CRDT re-export functions (`ast_to_crdt`, `crdt_to_source`)
- Fix the comment block: remove stale package paths, correct `CstNode` attribution

### 4. Update `src/benchmarks/`

Remove benchmark cases in `benchmark.mbt` and `performance_benchmark.mbt` that call
`ParsedDocument`. Replace with equivalent benchmarks against the real pipeline
(`IncrementalParser` or `ParserDb`) if the coverage gap is meaningful.

### 5. Update `CLAUDE.md` package map

Add the three undocumented packages:

| Package | Purpose |
|---------|---------|
| `src/token/` | `Token` enum + `TokenInfo` — the lambda token type |
| `src/syntax/` | `SyntaxKind` enum — symbolic names → `RawKind` integers for the CST |
| `src/benchmarks/` | Performance benchmarks for all pipeline layers |

## Success Criteria

- `moon test` still passes (368 tests, no regressions)
- `bash check-docs.sh` passes
- `src/pkg.generated.mbti` no longer references `@crdt`
- CLAUDE.md package map lists all 11 packages
- `src/lib.mbt` comment block matches actual package layout
