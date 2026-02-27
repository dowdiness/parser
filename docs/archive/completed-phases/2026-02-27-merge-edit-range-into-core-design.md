# Design: Merge `edit` + `range` into `core`

**Date:** 2026-02-27
**Status:** Approved

## Motivation

Preventative refactor. `core` (parser infrastructure), `edit` (`Edit` value type), and `range` (`Range` value type) are conceptually coupled — `Edit` drives incremental reparsing and `Range` tracks source spans used by the parser. Keeping them as separate packages creates a future cycle risk: if `core` ever needs to reference `Edit` or `Range` internally, and those packages reference `core`, MoonBit's build system would reject the cycle as a hard error.

Merging eliminates this risk entirely and reduces total package count from 13 to 11.

## Approach

Move `edit.mbt` and `range.mbt` (and their tests) into `src/core/`. Delete `src/edit/` and `src/range/`. Update all consumer `moon.pkg` import declarations and call-site aliases.

## File Changes

### Add to `src/core/`
- `edit.mbt` — moved from `src/edit/edit.mbt`, content unchanged
- `range.mbt` — moved from `src/range/range.mbt`, content unchanged
- `edit_test.mbt` — moved from `src/edit/edit_test.mbt`
- `range_test.mbt` — moved from `src/range/range_test.mbt`

### Modify
- `src/core/moon.pkg` — add `"moonbitlang/core/cmp"` import (required by `Range::minimum_by_length`)

### Delete
- `src/edit/` — entire directory
- `src/range/` — entire directory

## Import Updates (`moon.pkg`)

| Package | Remove | Add |
|---|---|---|
| `lexer` | `"dowdiness/parser/edit"` | `"dowdiness/parser/core" @core` |
| `crdt` | `"dowdiness/parser/edit"` | `"dowdiness/parser/core" @core` |
| `incremental` | `"dowdiness/parser/range"`, `"dowdiness/parser/edit"` | (already has `@core`) |
| `benchmarks` | `"dowdiness/parser/edit"` | `"dowdiness/parser/core" @core` |

## Call-site Updates

| Package | Before | After |
|---|---|---|
| `lexer` | `Edit::insert(...)` | `@core.Edit::insert(...)` |
| `crdt` | `Edit::new(...)` etc. | `@core.Edit::new(...)` etc. |
| `incremental` | `Edit`, `Range` (bare) | `@core.Edit`, `@core.Range` |
| `benchmarks` | `Edit::new(...)` | `@core.Edit::new(...)` |

## Resulting Dependency Graph

```
Before:
  edit  (no deps)
  range (@cmp)
  core  (@seam)

After:
  core  (@seam, @cmp)   ← absorbs edit + range
```

Packages that only used `edit` or `range` now import `core`, which transitively brings in `@seam`. Since `Edit` and `Range` APIs don't expose `@seam` types, this is inert — no new API surface is forced on callers.

## Verification

After the merge:
1. `moon check` — no type errors
2. `moon test` — all existing tests pass (edit and range tests migrate into core)
3. `moon info && moon fmt` — interfaces and formatting up to date
4. `git diff *.mbti` — verify `core` interface now includes `Edit` and `Range`; `edit` and `range` interfaces gone
