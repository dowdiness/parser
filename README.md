# Parser Module

Lexer and incremental parser for Lambda Calculus with arithmetic and conditionals.
Produces a lossless CST via `seam` (green-tree infrastructure), a typed AST,
and re-parses incrementally on edits via `ParserDb`.

## Quick Start

```bash
moon test              # 363 tests
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

| Package | Purpose |
|---------|---------|
| `src/lexer/` | Tokenizer + incremental `TokenBuffer` |
| `src/parser/` | CST parser, CST→AST conversion, lambda `LanguageSpec` |
| `seam/` | Language-agnostic CST (`CstNode`, `SyntaxNode`, `EventBuffer`) |
| `src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable` — shared primitives |
| `src/ast/` | `AstNode`, `Term`, pretty-printer |
| `src/pipeline/` | `ParserDb` — reactive incremental pipeline |
| `src/incremental/` | `IncrementalParser`, damage tracking |
| `src/viz/` | DOT graph renderer (`DotNode` trait) |
| `src/lambda/` | Lambda-specific `LambdaLanguage`, `LambdaParserDb` |

## Benchmarks

```bash
moon bench --package dowdiness/parser/benchmarks --release
```

Key benchmarks: `incremental vs full` (start/middle/end), `worst-case full
invalidation`, `best-case cosmetic change`. See [BENCHMARKS.md](BENCHMARKS.md).

## Testing

```bash
moon test                                    # all 363 tests
moon test --filter '*differential-fast*'     # CI-friendly differential
moon test --filter '*differential-long*'     # nightly fuzz pass
```
