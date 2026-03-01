# Rabbita-Style Monorepo Migration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure the project from a workspace-container-with-submodules into a rabbita-style multi-module monorepo named `loom`.

**Architecture:** Following `moonbit-community/rabbita`, the repo root has NO `moon.mod.json`. Each library (`loom/`, `seam/`, `incr/`) keeps its own `moon.mod.json` as an independent publishable module. The lambda example moves to `examples/lambda/` with its own module and path dep back to `../../loom`. Git submodules are eliminated; all source lives in one repo.

**Tech Stack:** MoonBit, moon tooling, git

---

## Current State

```
parser/                          ← github.com/dowdiness/parser
├── moon.mod.json                ← phantom module (no source packages)
├── .gitmodules                  ← 3 submodules: loom, seam, incr
├── loom/                        ← submodule → github.com/dowdiness/loom
│   └── src/
│       ├── core/
│       ├── bridge/
│       ├── pipeline/
│       ├── incremental/
│       ├── viz/
│       ├── benchmarks/
│       └── examples/lambda/     ← example bundled inside framework
├── seam/                        ← submodule → github.com/dowdiness/seam
├── incr/                        ← submodule → github.com/dowdiness/incr
└── docs/
```

## Target State

```
loom/                            ← github.com/dowdiness/loom (renamed repo)
├── loom/                        ← 📦 "dowdiness/loom" (core library)
│   ├── moon.mod.json
│   └── src/
│       ├── core/
│       ├── bridge/
│       ├── pipeline/
│       ├── incremental/
│       ├── viz/
│       └── benchmarks/
├── seam/                        ← 📦 "dowdiness/seam" (inlined, no submodule)
│   ├── moon.mod.json
│   └── *.mbt
├── incr/                        ← 📦 "dowdiness/incr" (inlined, no submodule)
│   ├── moon.mod.json
│   └── *.mbt, cells/, pipeline/, tests/, types/
├── examples/
│   └── lambda/                  ← 📦 "dowdiness/lambda-example" (own module)
│       ├── moon.mod.json        ← deps: { "dowdiness/loom": { "path": "../../loom" } }
│       └── src/
│           ├── lexer/
│           ├── token/
│           ├── syntax/
│           ├── ast/
│           └── (root pkg: parser, grammar, tests)
├── docs/
├── CLAUDE.md
├── README.md
├── ROADMAP.md
├── BENCHMARKS.md
├── LICENSE
└── check-docs.sh                ← NO root moon.mod.json, NO .gitmodules
```

## Dependency Direction (unchanged)

```
dowdiness/incr  ←  dowdiness/seam  ←  dowdiness/loom
(signals)          (CST infra)        (parser framework)
                                           ↑
                              dowdiness/lambda-example
                              (examples/lambda/, path dep)
```

## Test Counts (must preserve)

| Module | Tests | Command |
|--------|-------|---------|
| loom (framework only, no lambda) | ~100 | `cd loom && moon test` |
| lambda example | ~269 | `cd examples/lambda && moon test` |
| seam | 64 | `cd seam && moon test` |
| incr | 194 | `cd incr && moon test` |
| **Total** | **~627** | |

---

## Phase 1: Absorb Submodules Into Monorepo

This phase eliminates git submodules by inlining their content while preserving history.

### Task 1.1: Absorb `seam` submodule

**Context:** `seam/` is currently a git submodule pointing at `github.com/dowdiness/seam`. We need to remove the submodule and inline the files as regular tracked files.

**Step 1: Deinit the seam submodule**

```bash
git submodule deinit -f seam
git rm -f seam
rm -rf .git/modules/seam
```

**Step 2: Clone seam content back as regular files**

```bash
git clone https://github.com/dowdiness/seam.git seam_tmp
rm -rf seam_tmp/.git seam_tmp/.mooncakes seam_tmp/_build seam_tmp/.worktrees
mv seam_tmp seam
git add seam/
```

**Step 3: Verify seam builds and tests pass**

```bash
cd seam && moon test
```

Expected: 64 tests pass.

**Step 4: Commit**

```bash
git add .gitmodules seam/
git commit -m "refactor: absorb seam submodule into monorepo"
```

### Task 1.2: Absorb `incr` submodule

**Step 1: Deinit the incr submodule**

```bash
git submodule deinit -f incr
git rm -f incr
rm -rf .git/modules/incr
```

**Step 2: Clone incr content back as regular files**

```bash
git clone https://github.com/dowdiness/incr.git incr_tmp
rm -rf incr_tmp/.git incr_tmp/.mooncakes incr_tmp/_build incr_tmp/.worktrees
mv incr_tmp incr
git add incr/
```

**Step 3: Verify incr builds and tests pass**

```bash
cd incr && moon test
```

Expected: 194 tests pass.

**Step 4: Commit**

```bash
git add .gitmodules incr/
git commit -m "refactor: absorb incr submodule into monorepo"
```

### Task 1.3: Absorb `loom` submodule

**Step 1: Deinit the loom submodule**

```bash
git submodule deinit -f loom
git rm -f loom
rm -rf .git/modules/loom
```

**Step 2: Clone loom content back as regular files**

```bash
git clone https://github.com/dowdiness/loom.git loom_tmp
rm -rf loom_tmp/.git loom_tmp/.mooncakes loom_tmp/_build
mv loom_tmp loom
git add loom/
```

**Step 3: Verify loom builds and tests pass**

```bash
cd loom && moon test
```

Expected: 369 tests pass.

**Step 4: Delete `.gitmodules` (now empty) and commit**

```bash
rm .gitmodules
git add .gitmodules loom/
git commit -m "refactor: absorb loom submodule into monorepo

All three submodules (seam, incr, loom) are now regular directories.
.gitmodules deleted."
```

---

## Phase 2: Extract Lambda Example

The lambda example currently lives inside `loom/src/examples/lambda/`. Following the rabbita pattern, it should be a top-level `examples/lambda/` with its own `moon.mod.json`.

### Task 2.1: Create the lambda example module

**Step 1: Create `examples/lambda/` directory structure**

```bash
mkdir -p examples/lambda/src
```

**Step 2: Move lambda source files from loom**

```bash
mv loom/src/examples/lambda/lexer examples/lambda/src/lexer
mv loom/src/examples/lambda/token examples/lambda/src/token
mv loom/src/examples/lambda/syntax examples/lambda/src/syntax
mv loom/src/examples/lambda/ast examples/lambda/src/ast
# Root-level lambda files (parser, grammar, tests, etc.)
mv loom/src/examples/lambda/*.mbt examples/lambda/src/
mv loom/src/examples/lambda/moon.pkg examples/lambda/src/moon.pkg
```

**Step 3: Remove the now-empty examples directory from loom**

```bash
rm -rf loom/src/examples/
```

**Step 4: Create `examples/lambda/moon.mod.json`**

Create file `examples/lambda/moon.mod.json`:
```json
{
  "name": "dowdiness/lambda-example",
  "version": "0.1.0",
  "source": "src",
  "deps": {
    "dowdiness/loom": { "path": "../../loom" },
    "dowdiness/seam": { "path": "../../seam" },
    "moonbitlang/quickcheck": "0.9.10"
  },
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/loom",
  "license": "Apache-2.0",
  "keywords": ["lambda-calculus", "parser", "example"],
  "description": "Lambda calculus parser — example for dowdiness/loom"
}
```

**Step 5: Update all `moon.pkg` import paths**

Every `moon.pkg` under `examples/lambda/src/` currently uses `dowdiness/loom/examples/lambda/...` paths. These must change to `dowdiness/lambda-example/...`.

Update `examples/lambda/src/moon.pkg`:
```
import {
  "dowdiness/lambda-example/lexer",
  "dowdiness/lambda-example/ast",
  "dowdiness/loom/viz" @viz,
  "dowdiness/lambda-example/token",
  "dowdiness/lambda-example/syntax",
  "dowdiness/loom/core" @core,
  "dowdiness/seam" @seam,
  "moonbitlang/core/strconv",
  "dowdiness/loom/bridge" @bridge,
}

import {
  "moonbitlang/core/quickcheck",
} for "test"
```

Update `examples/lambda/src/lexer/moon.pkg`:
```
import {
  "dowdiness/lambda-example/token",
  "dowdiness/loom/core" @core,
}

import {
  "moonbitlang/quickcheck" @qc,
} for "test"
```

Update `examples/lambda/src/ast/moon.pkg`:
```
import {
  "moonbitlang/core/json",
}
```

Update `examples/lambda/src/token/moon.pkg`:
```
import {
  "dowdiness/loom/core" @core,
}
```

Update `examples/lambda/src/syntax/moon.pkg`:
```
import {
  "dowdiness/seam" @seam,
}
```

**Step 6: Update benchmarks `moon.pkg`**

`loom/src/benchmarks/moon.pkg` imports lambda packages. Update it:
```
import {
  "dowdiness/loom/core" @core,
  "dowdiness/lambda-example/lexer",
  "dowdiness/lambda-example" @lambda,
  "dowdiness/loom/incremental",
  "dowdiness/lambda-example/token",
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
  "dowdiness/loom/bridge" @bridge,
}
```

**BUT WAIT** — benchmarks in `loom/` can't depend on `dowdiness/lambda-example` because `loom/moon.mod.json` doesn't list it as a dep. Two options:

**(A) Move benchmarks to `examples/lambda/`** — they test the lambda parser, so they belong with the example. Create `examples/lambda/src/benchmarks/` and move the files there.

**(B) Create a separate benchmarks module** — `benchmarks/moon.mod.json` with deps on both loom and lambda-example.

**Recommended: Option A** — simpler, keeps benchmarks with the code they test.

```bash
mv loom/src/benchmarks/ examples/lambda/src/benchmarks/
```

Update `examples/lambda/src/benchmarks/moon.pkg`:
```
import {
  "dowdiness/loom/core" @core,
  "dowdiness/lambda-example/lexer",
  "dowdiness/lambda-example" @lambda,
  "dowdiness/loom/incremental",
  "dowdiness/lambda-example/token",
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
  "dowdiness/loom/bridge" @bridge,
}
```

**Step 7: Update `loom/moon.mod.json` — remove quickcheck dep if only used by lambda**

Check if any loom package (excluding examples/benchmarks) uses quickcheck. If not, remove it:
```json
{
  "name": "dowdiness/loom",
  "version": "0.1.0",
  "source": "src",
  "deps": {
    "dowdiness/seam": { "path": "../seam" },
    "dowdiness/incr": { "path": "../incr" }
  },
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/loom",
  "license": "Apache-2.0",
  "keywords": ["incremental", "parser", "cst", "grammar", "moonbit"],
  "description": "Generic parser framework: incremental parsing, CST building, grammar composition"
}
```

**Step 8: Create `examples/lambda/README.md`**

```markdown
# Lambda Calculus Parser

Example implementation of a lambda calculus parser using the
[dowdiness/loom](../../loom/) framework.

## Quick Start

```bash
moon test              # run all tests
moon bench --release   # benchmarks
```

## Packages

| Package | Purpose |
|---------|---------|
| `token/` | Token kinds (Ident, Lambda, Arrow, etc.) |
| `syntax/` | Syntax node kinds (Expression, Abstraction, etc.) |
| `lexer/` | Tokenizer |
| `ast/` | Abstract syntax tree |
| `src/` (root) | Parser, grammar, CST→AST conversion, tests |
| `benchmarks/` | Performance benchmarks |
```

**Step 9: Verify**

```bash
cd loom && moon test        # framework tests only (should be ~100)
cd ../examples/lambda && moon test   # lambda tests (~269)
cd ../../seam && moon test  # 64
cd ../incr && moon test     # 194
```

**Step 10: Commit**

```bash
git add -A
git commit -m "refactor: extract lambda example to examples/lambda/ with own module

Following rabbita pattern: examples are independent modules with path deps
back to the core library. Benchmarks move with the example they test."
```

---

## Phase 3: Delete Root `moon.mod.json` and Clean Up

### Task 3.1: Remove the phantom root module

**Step 1: Delete `moon.mod.json`**

```bash
rm moon.mod.json
```

**Step 2: Clean up build artifacts**

```bash
rm -rf _build target .mooncakes
```

**Step 3: Commit**

```bash
git add moon.mod.json
git commit -m "refactor: remove root moon.mod.json — no phantom module

Following rabbita pattern: repo root has no moon.mod.json.
Each subdirectory (loom/, seam/, incr/, examples/lambda/) is an
independent MoonBit module."
```

---

## Phase 4: Update Documentation

### Task 4.1: Rewrite README.md

Rewrite `README.md` for the new `loom` repo identity:

```markdown
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
```

**Step: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for loom monorepo identity"
```

### Task 4.2: Update CLAUDE.md

Update commands, package map, and references to match new layout. Key changes:
- Commands: remove `cd loom` prefix (you're already in the right module dir)
- Package map: add `examples/lambda/` as separate module
- Remove references to submodule workflow

### Task 4.3: Update `docs/README.md`

- Remove "Sibling Modules" section referencing submodule paths
- Update any `../loom/` relative links
- Update `development/managing-modules.md` → rewrite for monorepo workflow (no submodule steps)

### Task 4.4: Update `docs/development/managing-modules.md`

Rewrite from submodule workflow to monorepo workflow:
- Remove git submodule sections
- Add per-module development workflow (like rabbita)
- Keep publishing section but update paths

### Task 4.5: Run `check-docs.sh` and fix any warnings

```bash
bash check-docs.sh
```

### Task 4.6: Commit all docs updates

```bash
git add docs/ CLAUDE.md ROADMAP.md BENCHMARKS.md
git commit -m "docs: update all documentation for monorepo structure"
```

---

## Phase 5: GitHub Repo Rename and crdt Integration

### Task 5.1: Rename GitHub repo

On GitHub: `Settings → General → Repository name` → rename `parser` to `loom`.

GitHub auto-redirects the old URL, but update references:
- `crdt/.gitmodules`: change `parser` → `loom` URL
- All `moon.mod.json` `"repository"` fields already point to `dowdiness/loom` ✓

### Task 5.2: Update `crdt` repo submodule

In the `crdt` repo:

```bash
# Update .gitmodules
# [submodule "parser"] → [submodule "loom"]
#   path = loom          (was parser)
#   url = https://github.com/dowdiness/loom.git

git submodule deinit -f parser
git rm -f parser
git submodule add https://github.com/dowdiness/loom.git loom
git commit -m "refactor: rename parser submodule to loom after repo rename"
```

### Task 5.3: Update `crdt/moon.mod.json` if it references `dowdiness/parser`

Change any dep from:
```json
"dowdiness/parser": { "path": "parser" }
```
to:
```json
"dowdiness/loom": { "path": "loom" }
```

(Or `"path": "loom/loom"` if the crdt module needs the loom sub-module specifically.)

---

## Verification Checklist

After all phases, verify from repo root:

```bash
# All four modules build and test independently
cd loom && moon check && moon test && cd ..
cd seam && moon check && moon test && cd ..
cd incr && moon check && moon test && cd ..
cd examples/lambda && moon check && moon test && cd ../..

# Benchmarks run
cd examples/lambda && moon bench --release && cd ../..

# No root moon.mod.json
test ! -f moon.mod.json && echo "OK: no root module"

# No .gitmodules
test ! -f .gitmodules && echo "OK: no submodules"

# Docs check
bash check-docs.sh
```

Expected totals: ~100 (loom) + ~269 (lambda) + 64 (seam) + 194 (incr) = **~627 tests**.

---

## Rollback

If anything goes wrong mid-migration, the original submodule repos
(`dowdiness/loom`, `dowdiness/seam`, `dowdiness/incr`) remain untouched
on GitHub. You can always re-create submodules pointing at them.

The GitHub repo rename (`parser` → `loom`) can be reversed in repo settings.
