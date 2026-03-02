# Loom

A generic incremental parser framework for MoonBit.

## Modules

| Module | Path | Purpose |
|--------|------|---------|
| [`dowdiness/loom`](loom/) | `loom/` | Parser framework: incremental parsing, CST building, grammar composition |
| [`dowdiness/seam`](seam/) | `seam/` | Language-agnostic CST infrastructure |
| [`dowdiness/incr`](incr/) | `incr/` | Salsa-inspired incremental recomputation |

## Examples

| Example | Path | Purpose |
|---------|------|---------|
| [Lambda Calculus](examples/lambda/) | `examples/lambda/` | Full parser for λ-calculus with arithmetic |

## Quick Start

```bash
git clone https://github.com/dowdiness/loom.git
cd loom

# Core framework
cd loom && moon test && cd ..

# Lambda example
cd examples/lambda && moon test && cd ../..

# Benchmarks
cd examples/lambda && moon bench --release && cd ../..
```

## Documentation

- [docs/README.md](docs/README.md) — full navigation index
- [ROADMAP.md](ROADMAP.md) — phase status and future work
- [docs/development/managing-modules.md](docs/development/managing-modules.md) — multi-module workflow
