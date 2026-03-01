# Managing the Loom Project

This repo (`dowdiness/parser`) is a **development workspace** containing three library
submodules and their shared documentation. The actual source lives in `loom/`.

---

## Dependency Direction

```
dowdiness/incr  ←  dowdiness/seam  ←  dowdiness/loom
(signals)           (CST infra)         (parser framework)
                                              ↑
                                     examples/lambda/
                                     (lambda calculus demo)
```

`loom` is the product. The lambda example lives inside `loom/src/examples/lambda/` as a
first-party demonstration of the public API.

---

## Module Map

| Module | Path | GitHub | Purpose |
|--------|------|--------|---------|
| `dowdiness/loom` | `loom/` | [dowdiness/loom](https://github.com/dowdiness/loom) | Generic parser framework + lambda example |
| `dowdiness/seam` | `seam/` | [dowdiness/seam](https://github.com/dowdiness/seam) | Language-agnostic CST |
| `dowdiness/incr` | `incr/` | [dowdiness/incr](https://github.com/dowdiness/incr) | Reactive signals |

`dowdiness/parser` (this repo) has no source packages — it is a workspace container only.

---

## Initial Setup

```bash
git clone --recursive https://github.com/dowdiness/parser.git
```

If you already cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

---

## Daily Development

All source and tests live in `loom/`. Run everything from there:

```bash
cd loom
moon check                                    # lint
moon test                                     # 366 tests (framework + lambda example)
moon info && moon fmt                         # before every commit
moon bench --release                          # benchmarks
```

### Targeting a single package

```bash
moon test -p dowdiness/loom/examples/lambda/lexer
moon test -p dowdiness/loom/core
moon test -p dowdiness/loom/core -f edit_test.mbt
```

---

## Working Across Module Boundaries

`loom/`, `seam/`, and `incr/` are git submodules. Changes need a two-step commit:
push inside the submodule first, then update the pointer in this workspace repo.

### Making a change to loom

```bash
cd loom
# edit files
moon check && moon test
git add -p
git commit -m "feat: ..."
git push
cd ..
git add loom
git commit -m "chore: update loom submodule"
```

### Pulling the latest version of all submodules

```bash
git submodule update --remote
git add loom seam incr
git commit -m "chore: update submodule pointers"
```

### Syncing after someone else updated a pointer

```bash
git pull
git submodule update --init
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

Publish leaf deps first, then loom:

```bash
cd seam && moon publish && cd ..
cd incr && moon publish && cd ..
cd loom && moon publish && cd ..
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

> **Note:** `seam` and `incr` are not yet on mooncakes.io. The version-dep switch
> is blocked until they are published. Use path deps in the meantime.

### Required moon.mod.json fields

```json
{
  "name": "dowdiness/<module>",
  "version": "X.Y.Z",
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/<module>",
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
