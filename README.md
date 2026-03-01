# Parser Module

Lexer and incremental parser for Lambda Calculus with arithmetic and conditionals.
Produces a lossless CST via `seam` (green-tree infrastructure), a typed AST,
and re-parses incrementally on edits via `ParserDb`.

## Quick Start

```bash
moon test              # 293 parser tests
cd loom && moon test   # 76 loom framework tests (369 total)
moon check             # lint
moon info && moon fmt  # before commit
moon bench --release   # benchmarks (always --release)
```

## Documentation

- [docs/README.md](docs/README.md) — full navigation index
- [ROADMAP.md](ROADMAP.md) — architecture, phase status, future work
- [docs/architecture/overview.md](docs/architecture/overview.md) — layer diagram + principles
- [docs/api/reference.md](docs/api/reference.md) — public API reference
- [docs/architecture/language.md](docs/architecture/language.md) — grammar and syntax

## Module Map

**`dowdiness/parser`** — lambda calculus example/application:

| Package | Purpose |
|---------|---------|
| `src/examples/lambda/token/` | `Token` enum + `TokenInfo` |
| `src/examples/lambda/syntax/` | `SyntaxKind` enum — kind names → `RawKind` integers |
| `src/examples/lambda/lexer/` | Tokenizer + incremental `TokenBuffer` |
| `src/examples/lambda/ast/` | `AstNode`, `Term`, pretty-printer |
| `src/examples/lambda/` | `lambda_grammar`, `to_dot`, low-level CST parsing |

**`dowdiness/loom`** (`loom/`) — reusable parser framework (zero lambda deps):

| Package | Purpose |
|---------|---------|
| `loom/src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable`, `ParserContext[T,K]` |
| `loom/src/bridge/` | `Grammar[T,K,Ast]`, factory functions for `IncrementalParser` + `ParserDb` |
| `loom/src/pipeline/` | `ParserDb` — reactive incremental pipeline |
| `loom/src/incremental/` | `IncrementalParser`, damage tracking |
| `loom/src/viz/` | DOT graph renderer (`DotNode` trait) |

## Benchmarks

`moon bench --package dowdiness/parser/benchmarks --release` — incremental vs full, worst-case, cosmetic change. See [BENCHMARKS.md](BENCHMARKS.md).

## Testing

```bash
moon test && (cd loom && moon test)          # all 369 tests (293 + 76)
moon test --filter '*differential-fast*'     # CI-friendly differential
moon test --filter '*differential-long*'     # nightly fuzz pass
```
