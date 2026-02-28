# Examples Folder Design

**Date:** 2026-03-01
**Status:** Approved

## Goal

Move all lambda-calculus-specific packages out of the top-level `src/` directory and
into `src/examples/lambda/`, making the separation between "reusable library" and
"example language implementation" structurally visible in the file tree.

## Target Structure

```
src/
  examples/
    lambda/              ← dowdiness/parser/examples/lambda
      ast/               ← dowdiness/parser/examples/lambda/ast
      token/             ← dowdiness/parser/examples/lambda/token
      syntax/            ← dowdiness/parser/examples/lambda/syntax
      lexer/             ← dowdiness/parser/examples/lambda/lexer
  core/
  incremental/
  pipeline/
  viz/
  lib.mbt
  moon.pkg
```

## Packages Moved

| Old path | New path |
|---|---|
| `src/ast/` | `src/examples/lambda/ast/` |
| `src/token/` | `src/examples/lambda/token/` |
| `src/syntax/` | `src/examples/lambda/syntax/` |
| `src/lexer/` | `src/examples/lambda/lexer/` |
| `src/lambda/` | `src/examples/lambda/` |

## Packages Unchanged

`src/core/`, `src/incremental/`, `src/pipeline/`, `src/viz/`,
`seam/` (local path dep), `incr/` (local path dep).

## Import Path Updates

Four `moon.pkg` files need updated import strings. No `.mbt` logic changes.

| File | Paths to update |
|---|---|
| `src/moon.pkg` | `parser/token`, `parser/ast`, `parser/lexer`, `parser/lambda` |
| `src/benchmarks/moon.pkg` | `parser/lexer`, `parser/lambda`, `parser/token` |
| `src/examples/lambda/moon.pkg` | `parser/lexer`, `parser/ast`, `parser/token`, `parser/syntax` → sibling paths |
| `src/lib.mbt` | Header comment package path strings |

## Verification

```bash
moon check
moon test          # all 363 tests pass
moon info && moon fmt
```
