# Managing the Loom Monorepo

This repo (`dowdiness/loom`) is a **rabbita-style multi-module monorepo**: the root
has no `moon.mod.json`. Each subdirectory is an independent, publishable MoonBit module.

---

## Module Map

| Module | Path | Purpose |
|--------|------|---------|
| `dowdiness/loom` | `loom/` | Generic parser framework (core, bridge, pipeline, incremental, viz) |
| `dowdiness/seam` | `seam/` | Language-agnostic CST (`CstNode`, `SyntaxNode`) |
| `dowdiness/incr` | `incr/` | Salsa-inspired reactive signals (`Signal`, `Memo`) |
| `dowdiness/lambda` | `examples/lambda/` | Lambda calculus parser — example for loom |

---

## Dependency Direction

```
dowdiness/incr  ←──┐
(signals)          ├── dowdiness/loom
dowdiness/seam  ←──┘   (parser framework)
(CST infra)        ↑          ↑
                   │   dowdiness/lambda
                   └── (examples/lambda/, path dep)
```

`seam` and `incr` are independent — neither depends on the other.
`lambda` depends on both `loom` (path) and `seam` (path, direct import in syntax/).

---

## Daily Development

Each module is self-contained. Run `moon` commands from the module's directory:

```bash
cd loom && moon check && moon test    # 76 tests (framework only)
cd seam && moon check && moon test    # 64 tests
cd incr && moon check && moon test    # 194 tests
cd examples/lambda && moon check && moon test   # 293 tests
```

### Before every commit (in the module you edited)

```bash
moon info && moon fmt   # regenerate .mbti interfaces + format
```

### Targeting a single package

```bash
# From loom/
moon test -p dowdiness/loom/core
moon test -p dowdiness/loom/core -f edit_test.mbt

# From examples/lambda/
moon test -p dowdiness/lambda/lexer
moon test -p dowdiness/lambda/lexer -f lexer_test.mbt
```

---

## Cross-Module Changes

Changes to `seam` or `incr` that affect `loom` or `lambda` are tested by running
the dependent module. Because all modules live in the same repo and use path deps,
there is no two-step submodule commit: just edit, test, and commit everything together.

```bash
# Example: change seam, verify loom still builds
cd seam && moon check && moon test
cd ../loom && moon check && moon test
git add seam/ loom/
git commit -m "feat: extend seam API and update loom callers"
```

---

## Publishing to mooncakes.io

Each module is published independently with `moon publish` from that module's root.

### Prerequisites

```bash
moon register   # first time only
moon login      # subsequent sessions
```

### Publish order

Publish leaf deps first:

```bash
cd seam && moon publish && cd ..
cd incr && moon publish && cd ..
cd loom && moon publish && cd ..
cd examples/lambda && moon publish && cd ../..
```

### Path deps → version deps before publishing

`moon publish` requires all deps to be version deps. Before publishing `loom`, edit
`loom/moon.mod.json` to switch path deps to the just-published versions:

```json
"deps": {
  "dowdiness/seam": "0.1.0",
  "dowdiness/incr": "0.3.2"
}
```

After publishing, revert to path deps for local development:

```bash
git checkout loom/moon.mod.json
```

### Required moon.mod.json fields

```json
{
  "name": "dowdiness/<module>",
  "version": "X.Y.Z",
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/loom",
  "license": "Apache-2.0",
  "keywords": ["..."],
  "description": "..."
}
```

### Version bumping

| Change | Bump |
|--------|------|
| Incompatible API change | MAJOR |
| New backward-compatible feature | MINOR |
| Bug fix | PATCH |
