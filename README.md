# Parser Workspace

Development workspace for `dowdiness/loom` — a generic incremental parser framework for MoonBit.

The lambda calculus parser and all source packages now live in `loom/`.
This repo holds the git submodules (`loom/`, `seam/`, `incr/`) and documentation.

## Quick Start

```bash
git clone --recursive https://github.com/dowdiness/parser.git
cd parser/loom
moon test              # 369 tests
moon check             # lint
moon info && moon fmt  # before commit
moon bench --release   # benchmarks (always --release)
```

## Documentation

- [docs/README.md](docs/README.md) — full navigation index
- [ROADMAP.md](ROADMAP.md) — architecture, phase status, future work
- [docs/development/managing-modules.md](docs/development/managing-modules.md) — submodule + publish workflow

## Module Map

**`dowdiness/loom`** (`loom/`) — parser framework + lambda calculus example:

| Package | Purpose |
|---------|---------|
| `loom/src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable`, `ParserContext[T,K]` |
| `loom/src/bridge/` | `Grammar[T,K,Ast]`, factory functions for `IncrementalParser` + `ParserDb` |
| `loom/src/pipeline/` | `ParserDb` — reactive incremental pipeline |
| `loom/src/incremental/` | `IncrementalParser`, damage tracking |
| `loom/src/viz/` | DOT graph renderer (`DotNode` trait) |
| `loom/src/examples/lambda/` | Lambda calculus demo: token, syntax, lexer, ast, grammar |
| `loom/src/benchmarks/` | Performance benchmarks for all pipeline layers |
