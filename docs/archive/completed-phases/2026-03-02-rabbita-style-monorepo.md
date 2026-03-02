# Rabbita-Style Monorepo Migration Plan

**Status:** Complete (Phases 1–4 merged on `refactor/rabbita-monorepo`; Phase 5 = manual GitHub repo rename, pending user action)

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
│       └── viz/
├── seam/                        ← 📦 "dowdiness/seam" (inlined, no submodule)
│   ├── moon.mod.json
│   └── *.mbt
├── incr/                        ← 📦 "dowdiness/incr" (inlined, no submodule)
│   ├── moon.mod.json
│   └── *.mbt, cells/, pipeline/, tests/, types/
├── examples/
│   └── lambda/                  ← 📦 "dowdiness/lambda-example" (own module)
│       ├── moon.mod.json        ← deps: loom (path), seam (path), quickcheck
│       └── src/
│           ├── lexer/
│           ├── token/
│           ├── syntax/
│           ├── ast/
│           ├── benchmarks/
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
dowdiness/incr ←──┐
(signals)         ├── dowdiness/loom
dowdiness/seam ←──┘   (parser framework)
(CST infra)       ↑          ↑
                  │   dowdiness/lambda-example
                  └── (examples/lambda/, path dep)
```

> Lambda-example depends on both loom (path) and seam (path, direct import in syntax/).
> seam and incr are independent — neither depends on the other.

## Test Counts (must preserve)

| Module | Tests | Command |
|--------|-------|---------|
| loom (framework only, no lambda) | ~76 | `cd loom && moon test` |
| lambda example | ~293 | `cd examples/lambda && moon test` |
| seam | 64 | `cd seam && moon test` |
| incr | 194 | `cd incr && moon test` |
| **Total** | **~627** | |

> **Note:** loom currently has 369 tests (76 framework + 293 lambda). After extracting
> lambda, loom retains only the ~76 framework tests. The lambda module gets the ~293.

---

## Phase 1: Absorb Submodules Into Monorepo

This phase eliminates git submodules by inlining their content while preserving history.

**Approach chosen:** use `git subtree add` (without `--squash`) at the exact submodule
gitlink commits currently pinned in this repo.

**Preflight: ensure submodule gitdirs exist and capture pinned SHAs**

```bash
git submodule update --init seam incr loom
git ls-tree HEAD seam incr loom | awk '{print $4"="$3}' > .submodule-refs
cat .submodule-refs          # verify: seam=<sha>, incr=<sha>, loom=<sha>
source .submodule-refs       # sets $seam, $incr, $loom
```

> Re-run `source .submodule-refs` if you start a new shell session mid-migration.

### Task 1.1: Absorb `seam` submodule

**Context:** `seam/` is currently a git submodule pointing at `github.com/dowdiness/seam`. We need to remove the submodule and inline the files as regular tracked files.

**Step 1: Remove the seam submodule and commit**

```bash
git submodule deinit -f seam
git rm -f seam
git commit -m "chore: remove seam submodule entry"
```

**Step 2: Import seam history with subtree at pinned commit**

```bash
git subtree add --prefix=seam .git/modules/seam "$seam" -m "refactor: absorb seam submodule into monorepo (preserve history)"
rm -rf .git/modules/seam
```

**Step 3: Verify seam builds and tests pass**

```bash
cd seam && moon test
```

Expected: 64 tests pass.

**Step 4: Confirm commit**
`git subtree add` already created the absorb commit.

### Task 1.2: Absorb `incr` submodule

**Step 1: Remove the incr submodule and commit**

```bash
git submodule deinit -f incr
git rm -f incr
git commit -m "chore: remove incr submodule entry"
```

**Step 2: Import incr history with subtree at pinned commit**

```bash
git subtree add --prefix=incr .git/modules/incr "$incr" -m "refactor: absorb incr submodule into monorepo (preserve history)"
rm -rf .git/modules/incr
```

**Step 3: Verify incr builds and tests pass**

```bash
cd incr && moon test
```

Expected: 194 tests pass.

**Step 4: Confirm commit**
`git subtree add` already created the absorb commit.

### Task 1.3: Absorb `loom` submodule

**Step 1: Remove the loom submodule and commit**

```bash
git submodule deinit -f loom
git rm -f loom
git commit -m "chore: remove loom submodule entry"
```

**Step 2: Import loom history with subtree at pinned commit**

```bash
git subtree add --prefix=loom .git/modules/loom "$loom" -m "refactor: absorb loom submodule into monorepo (preserve history)"
rm -rf .git/modules/loom
```

**Step 3: Verify loom builds and tests pass**

`.mooncakes/` is gitignored in the loom repo, so `git subtree add` does not import it —
no stale cache cleanup needed.

```bash
cd loom && moon test
```

Expected: 369 tests pass.

**Step 4: Clean up refs file; delete `.gitmodules` only if still present**

```bash
rm -f .submodule-refs
if test -f .gitmodules; then
  rm .gitmodules
  git add .gitmodules
  git commit -m "chore: delete empty .gitmodules"
fi
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
# Preserve package API snapshots and docs
test -f loom/src/examples/lambda/pkg.generated.mbti && mv loom/src/examples/lambda/pkg.generated.mbti examples/lambda/src/pkg.generated.mbti
test -f loom/src/examples/lambda/README.md && mv loom/src/examples/lambda/README.md examples/lambda/README.md
```

**Step 3: Remove only the migrated lambda directory**

```bash
rmdir loom/src/examples/lambda
rmdir loom/src/examples 2>/dev/null || true
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

**Step 6: Move benchmarks to `examples/lambda/` and update imports**

Benchmarks currently live at `loom/src/benchmarks/` but depend on lambda packages.
To keep module deps clean, move them into the lambda module.

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

**Step 7: Remove quickcheck dep from `loom/moon.mod.json`**

quickcheck is only used by the lambda example (lexer tests + root package tests).
No loom framework package (core, bridge, pipeline, incremental, viz) imports it.
Lambda-example declares its own quickcheck dep, so loom no longer needs it. Target state:
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

**Step 8: Create or update `examples/lambda/README.md`**

Write `examples/lambda/README.md` with this content (note: use real backtick fences,
not the escaped representation shown here):

```
# Lambda Calculus Parser

Example implementation of a lambda calculus parser using the
[dowdiness/loom](../../loom/) framework.

## Quick Start

(bash fence)
moon test              # run all tests
moon bench --release   # benchmarks
(end fence)

## Packages

| Package | Purpose |
|---------|---------|
| token/      | Token kinds (Ident, Lambda, Arrow, etc.) |
| syntax/     | Syntax node kinds (Expression, Abstraction, etc.) |
| lexer/      | Tokenizer |
| ast/        | Abstract syntax tree |
| src/ (root) | Parser, grammar, CST→AST conversion, tests |
| benchmarks/ | Performance benchmarks |
```

**Step 9: Verify**

```bash
cd loom && moon test              # framework tests only (~76, not ~100 — see test table)
cd ../examples/lambda && moon test # lambda tests (~293)
cd ../../seam && moon test         # 64
cd ../incr && moon test            # 194
```

**Step 10: Commit**

```bash
git add examples/ loom/src/ loom/moon.mod.json
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

**Step 3: Update `repository` fields in absorbed modules**

`seam/moon.mod.json` and `incr/moon.mod.json` still point to their old standalone
repos. Update them to the new monorepo:

In `seam/moon.mod.json`, change:
```json
"repository": "https://github.com/dowdiness/seam"
```
to:
```json
"repository": "https://github.com/dowdiness/loom"
```

In `incr/moon.mod.json`, change:
```json
"repository": "https://github.com/dowdiness/incr"
```
to:
```json
"repository": "https://github.com/dowdiness/loom"
```

**Step 4: Commit**

```bash
git add moon.mod.json seam/moon.mod.json incr/moon.mod.json
git commit -m "refactor: remove root moon.mod.json, update repository URLs

Following rabbita pattern: repo root has no moon.mod.json.
Each subdirectory (loom/, seam/, incr/, examples/lambda/) is an
independent MoonBit module. Repository fields now point to the monorepo."
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
to the specific sub-module needed. Since the repo now has no root `moon.mod.json`,
the path must point into a sub-directory:
```json
"dowdiness/loom":         { "path": "loom/loom" },
"dowdiness/lambda-example": { "path": "loom/examples/lambda" }
```

### Task 5.4: Audit `crdt` source for stale `dowdiness/parser/...` import paths

`moon.mod.json` path dep changes alone are not enough — MoonBit source files that
import `dowdiness/parser/examples/lambda/...` or `dowdiness/parser/benchmarks/...`
will also need updating. Search before committing:

```bash
grep -r "dowdiness/parser" crdt/
```

Update each hit to use `dowdiness/loom/...` or `dowdiness/lambda-example/...`
depending on which package is being imported. Run `moon check` in crdt afterward.

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

Expected totals: ~76 (loom) + ~293 (lambda) + 64 (seam) + 194 (incr) = **~627 tests**.

---

## Rollback

If anything goes wrong mid-migration, the original submodule repos
(`dowdiness/loom`, `dowdiness/seam`, `dowdiness/incr`) remain untouched
on GitHub. You can always re-create submodules pointing at them.

The GitHub repo rename (`parser` → `loom`) can be reversed in repo settings.
