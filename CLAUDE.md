# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Commands

```bash
moon check              # lint
moon test               # 353 tests
moon info && moon fmt   # update .mbti interfaces + format (always before commit)
moon bench --release    # benchmarks (always --release)
bash check-docs.sh      # validate docs hierarchy (line limits, orphaned files, completed plans)
```

Run a single package or file:
```bash
moon test -p dowdiness/parser/src/core
moon test -p dowdiness/parser/src/lexer -f lexer_test.mbt
```

## Package Map

| Package | Purpose |
|---------|---------|
| `src/token/` | `Token` enum + `TokenInfo` — the lambda token type (`T` in `ParserContext[T, K]`) |
| `src/syntax/` | `SyntaxKind` enum — symbolic kind names → `RawKind` integers for the CST |
| `src/lexer/` | Tokenizer + incremental `TokenBuffer` |
| `src/parser/` | CST parser, CST→AST conversion, lambda `LanguageSpec` |
| `src/seam/` | Language-agnostic CST (`CstNode`, `SyntaxNode`, `EventBuffer`) |
| `src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable` — shared primitives |
| `src/ast/` | `AstNode`, `Term`, pretty-printer |
| `src/pipeline/` | `ParserDb` — reactive incremental pipeline |
| `src/incremental/` | `IncrementalParser`, damage tracking |
| `src/viz/` | DOT graph renderer (`DotNode` trait) |
| `src/bridge/` | `Grammar[T,K,Ast]`, factory functions for `IncrementalParser` + `ParserDb` |
| `src/examples/lambda/` | `lambda_grammar`, `to_dot`, low-level CST parsing API |
| `src/benchmarks/` | Performance benchmarks for all pipeline layers |

## Architecture

**Reactive pipeline:** `Signal[String]` → `Memo[CstStage]` → `Memo[AstNode]`
(TokenStage was removed — see ADR `docs/decisions/2026-02-27-remove-tokenStage-memo.md`)

**Two-tree model:** `CstNode` (immutable, position-independent, structurally shareable) +
`SyntaxNode` (ephemeral positioned facade). All callers use `SyntaxNode`; `.cst` is private.

**Edit protocol:** `Edit { start, old_len, new_len }` — lengths not endpoints.
`pub trait Editable { start/old_len/new_len }` implemented by `Edit`.
`TextDelta (Retain|Insert|Delete)` → `.to_edits()` → `[Edit]` (planned).

**Subtree reuse:** `ReuseCursor` 4-condition protocol (kind + leading token context +
trailing token context + no damage overlap). O(depth) per lookup via stateful frame stack.

Full architecture: `docs/architecture/` | Design decisions: `docs/decisions/`

## Docs Rules

**Where files belong:**

| Type | Location |
|------|----------|
| Active / future plan | `docs/plans/` |
| Completed plan | `docs/archive/completed-phases/` |
| Architecture explanation | `docs/architecture/` |
| API reference | `docs/api/` |
| Correctness / testing | `docs/correctness/` |
| Benchmarks / performance | `docs/performance/` |
| Stale status docs, research notes | `docs/archive/` |
| Top-level navigation | `README.md` (≤60 lines) · `ROADMAP.md` (≤450 lines) |

**Three rules:**

1. **Navigation stays current.** Any commit that adds, moves, or removes a `.md` file
   must update `docs/README.md` in the same commit. The index is the entry point for
   AI agents — an unlisted file is effectively invisible.

2. **Archive on completion.** When a plan's last task is done:
   - Add `**Status:** Complete` near the top of the plan file
   - `git mv docs/plans/<plan>.md docs/archive/completed-phases/<plan>.md`
   - Update `docs/README.md` (move entry from Active Plans → Archive)
   - `bash check-docs.sh` should show no warnings before committing
   Do this in the same commit that marks the plan complete, not later.

3. **Top-level docs stay slim.** `README.md` and `ROADMAP.md` are summaries with links,
   not detail documents. Extract any section >20 lines into a sub-doc and link to it.

## MoonBit Conventions

- Tests: `///|` doc-comment prefix + `test "name" { ... }` blocks
- Assertions: `inspect(expr, content="expected")`
- Panic tests: name starts with `"panic "` — test runner expects `abort()`
- Whitebox tests (`*_wbtest.mbt`): same package, access private fields
- Anonymous callbacks: `() => expr`, `() => { stmts }`, `x => expr`. Empty body: `() => ()` not `() => {}`
- Trait impl: one `pub impl Trait for Type with method(self) { ... }` per method
- Orphan rule (error 4061): can't impl foreign trait for foreign type — use a private newtype wrapper

## Key Design Decisions

- `Edit` stores lengths (`old_len`, `new_len`), not endpoints — matches Loro/Quill/diamond-types
- `TokenStage` memo removed — vacuous for whitespace-inclusive lexers (ADR 2026-02-27)
- `ReuseCursor` uses trailing-context check (Option B) to prevent false reuse
- `ParserContext` is generic `[T, K]` — any grammar can plug in via `LanguageSpec`
