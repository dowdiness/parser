# Examples Folder Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move all lambda-calculus-specific packages into `src/examples/lambda/`, leaving only reusable infrastructure in `src/`.

**Architecture:** Five directories (`lambda/`, `ast/`, `token/`, `syntax/`, `lexer/`) are relocated under `src/examples/lambda/` using `git mv`. No `.mbt` source files change — only `moon.pkg` import strings are updated to reflect the new paths. Default package aliases are preserved (last path segment stays the same).

**Tech Stack:** MoonBit, `moon` build tool

---

### Task 1: Move the five packages

**Files:**
- Move: `src/lambda/` → `src/examples/lambda/`
- Move: `src/ast/` → `src/examples/lambda/ast/`
- Move: `src/token/` → `src/examples/lambda/token/`
- Move: `src/syntax/` → `src/examples/lambda/syntax/`
- Move: `src/lexer/` → `src/examples/lambda/lexer/`

**Step 1: Create the examples directory and move all packages**

```bash
mkdir -p src/examples
git mv src/lambda src/examples/lambda
git mv src/ast src/examples/lambda/ast
git mv src/token src/examples/lambda/token
git mv src/syntax src/examples/lambda/syntax
git mv src/lexer src/examples/lambda/lexer
```

**Step 2: Verify git sees the moves**

```bash
git status
```

Expected: 5 directories renamed, e.g. `renamed: src/lambda/... -> src/examples/lambda/...`

**Step 3: Confirm moon check fails (expected — imports are broken)**

```bash
moon check 2>&1 | head -20
```

Expected: errors referencing `dowdiness/parser/token`, `dowdiness/parser/ast`, `dowdiness/parser/lexer`, `dowdiness/parser/lambda`, `dowdiness/parser/syntax` not found.

---

### Task 2: Update `src/examples/lambda/moon.pkg`

This is the moved lambda package. It imports the four sibling packages by their old paths.

**Files:**
- Modify: `src/examples/lambda/moon.pkg`

**Step 1: Replace the four lambda-specific import paths**

Replace the entire file with:

```
import {
  "dowdiness/parser/pipeline" @pipeline,
  "dowdiness/parser/examples/lambda/lexer",
  "dowdiness/parser/examples/lambda/ast",
  "dowdiness/parser/viz" @viz,
  "dowdiness/parser/examples/lambda/token",
  "dowdiness/parser/examples/lambda/syntax",
  "dowdiness/parser/core" @core,
  "dowdiness/seam" @seam,
  "moonbitlang/core/strconv",
  "dowdiness/parser/incremental" @incremental,
}

import {
  "moonbitlang/core/quickcheck",
} for "test"
```

**Step 2: Verify moon check still shows remaining errors (not this package)**

```bash
moon check 2>&1 | grep "not found"
```

Expected: errors now only from `src/moon.pkg`, `src/benchmarks/moon.pkg`, and `src/examples/lambda/lexer/moon.pkg`.

---

### Task 3: Update `src/examples/lambda/lexer/moon.pkg`

The lexer imports `token`, which has moved.

**Files:**
- Modify: `src/examples/lambda/lexer/moon.pkg`

**Step 1: Update the token import path**

Replace the entire file with:

```
import {
  "dowdiness/parser/examples/lambda/token",
  "dowdiness/parser/core" @core,
}

import {
  "moonbitlang/core/quickcheck" @qc,
} for "test"
```

---

### Task 4: Update `src/moon.pkg`

The top-level lib facade imports four moved packages.

**Files:**
- Modify: `src/moon.pkg`

**Step 1: Update the four lambda-specific import paths**

Replace the entire file with:

```
import {
  "dowdiness/parser/examples/lambda/token",
  "dowdiness/parser/examples/lambda/ast",
  "dowdiness/parser/examples/lambda/lexer",
  "dowdiness/parser/examples/lambda" @lambda,
}
```

---

### Task 5: Update `src/benchmarks/moon.pkg`

The benchmarks package imports lexer, lambda, and token.

**Files:**
- Modify: `src/benchmarks/moon.pkg`

**Step 1: Update the three lambda-specific import paths**

Replace the entire file with:

```
import {
  "dowdiness/parser/core" @core,
  "dowdiness/parser/examples/lambda/lexer",
  "dowdiness/parser/examples/lambda" @lambda,
  "dowdiness/parser/incremental",
  "dowdiness/parser/examples/lambda/token",
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
}
```

---

### Task 6: Update `src/lib.mbt` header comment

The comment block at the top of `src/lib.mbt` documents subpackage paths for callers.

**Files:**
- Modify: `src/lib.mbt`

**Step 1: Update the four lambda-specific paths in the comment**

Find the comment block (lines 1–16) and update:

```
// Root package facade for dowdiness/parser
//
// This module re-exports the primary API entry points. For the full API,
// import subpackages directly:
//
//   dowdiness/parser/examples/lambda/token   - Token, TokenInfo
//   dowdiness/parser/core                    - Edit, Range, ReuseSlot (shared primitives)
//   dowdiness/parser/examples/lambda/ast     - AstNode, AstKind, Term, Bop
//   dowdiness/parser/examples/lambda/lexer   - tokenize, TokenBuffer
//   dowdiness/parser/examples/lambda/syntax  - SyntaxKind enum (token + node kind names)
//   dowdiness/parser/examples/lambda         - parse, parse_tree, parse_with_error_recovery,
//                                             LambdaIncrementalParser, LambdaParserDb, LambdaLanguage,
//                                             DotNode impl for AstNode
//   dowdiness/parser/incremental             - IncrementalParser, DamageTracker
//   dowdiness/parser/viz                     - DotNode (trait), to_dot[T : DotNode]
//   dowdiness/parser/pipeline                - ParserDb — reactive incremental pipeline
```

---

### Task 7: Verify, regenerate interfaces, and commit

**Step 1: Run moon check — must pass with zero errors**

```bash
moon check
```

Expected: no errors.

**Step 2: Run full test suite — all tests must pass**

```bash
moon test
```

Expected: all 363 tests pass (or the current count).

**Step 3: Regenerate `.mbti` interface files and format**

```bash
moon info && moon fmt
```

**Step 4: Check docs hierarchy**

```bash
bash check-docs.sh
```

Expected: no warnings.

**Step 5: Mark the design doc as complete and move it to archive**

Add `**Status:** Complete` near the top of `docs/plans/2026-03-01-examples-folder-design.md`, then:

```bash
git mv docs/plans/2026-03-01-examples-folder-design.md docs/archive/completed-phases/2026-03-01-examples-folder-design.md
```

Update `docs/README.md`: move the design entry from Active Plans → Archive.

**Step 6: Commit everything**

```bash
git add -A
git commit -m "refactor: move lambda packages to src/examples/lambda/

ast, token, syntax, lexer, lambda → src/examples/lambda/{ast,token,syntax,lexer,}
Update moon.pkg imports in lambda, lexer, src root, and benchmarks.
No .mbt logic changes; all 363 tests pass."
```
