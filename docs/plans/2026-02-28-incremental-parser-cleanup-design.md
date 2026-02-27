# Design: Remove `adjust_tree_positions` / `expand_for_tree` Holdover

**Created:** 2026-02-28
**Status:** Approved

## Problem

`IncrementalParser::edit()` contains a vestigial two-step sequence inherited from before the
green tree (`SyntaxNode`) became the primary incremental state:

```
Step 3: adjust_tree_positions(old_tree, edit)   — O(n) walk of AstNode
Step 4: DamageTracker::expand_for_tree(adjusted_tree) — O(n) walk of AstNode
         → damaged_range
```

Both walks are redundant:

1. **`expand_for_tree` is a no-op.** It expands the damage range to cover any AstNode that
   overlaps the edit. But `ReuseCursor` — initialized with `damaged_range.start/end` —
   already refuses to reuse any CST node that overlaps those bounds. The expansion produces
   the same result the cursor would have produced without it.

2. **`adjust_tree_positions` doesn't change `expand_for_tree`'s output.** Position adjustment
   shifts nodes that are *after* the edit. Those nodes can't overlap the edit range by
   definition, so `expand_for_tree` ignores them regardless. Overlapping nodes are left at
   their pre-edit positions in both paths.

3. **The whole-tree reuse check is a dead code path.** `incremental_reparse` checks
   `can_reuse_node(adjusted_tree, damaged_range)` to see if the entire tree is undamaged.
   For a root node spanning `[0..source.length()]`, this fires only when
   `edit.start >= source.length()` — an out-of-bounds edit. All valid edits fail this check.

4. **`self.tree` is used as a sentinel for "has initial parse run."** After removing the above,
   `old_tree` is consumed only for that guard. `self.syntax_tree` has the identical lifecycle
   and is a cleaner sentinel.

## Changes

### `src/incremental/incremental_parser.mbt`

**Struct:** Add `// output-only` comment to `tree` field to make the data-flow intent explicit.

**`edit()`:** Replace steps 3–5 with direct damage range construction:
```moonbit
// BEFORE
let adjusted_tree = self.adjust_tree_positions(old_tree, edit)
let damage = DamageTracker::new(edit)
damage.expand_for_tree(adjusted_tree)
let damaged_range = damage.range()
let new_tree = self.incremental_reparse(new_source, damaged_range, adjusted_tree, tokens)

// AFTER
let damaged_range = @core.Range::new(edit.start, edit.new_end())
let new_tree = self.incremental_reparse(new_source, damaged_range, tokens)
```

Change the initial-parse sentinel from `self.tree` to `self.syntax_tree`:
```moonbit
// BEFORE
let old_tree = match self.tree { Some(t) => t; None => return self.parse() }

// AFTER
if self.syntax_tree.is_none() { return self.parse() }
```

**`incremental_reparse()`:** Remove `adjusted_tree` parameter and the whole-tree reuse
check (lines 194–201).

**Remove methods** (no callers after above):
- `adjust_tree_positions()` (~43 lines)
- `can_reuse_node()` (~10 lines)

### `src/incremental/damage.mbt`

**Remove `expand_for_tree()`** (~30 lines). The remaining `DamageTracker` API
(`expand_for_node`, `add_range`, `is_damaged`, `range`, `stats`) is kept — used in tests
and available for future use.

## What Does NOT Change

- `TokenBuffer` incremental re-lex path
- `ReuseCursor` subtree reuse (cursor still receives `damaged_range.start/end`)
- `DamageTracker::new(edit)` — no longer called from `edit()`, but kept for tests
- `get_tree()`, `get_source()`, `stats()`, `get_last_reuse_count()` public API
- `parse()` path (untouched)
- All error/tokenization fallback paths

## Why the `ReuseCursor` Is Sufficient Without Pre-Expansion

`make_reuse_cursor` receives `damaged_range.start` and `damaged_range.end`. Inside
`ReuseCursor::try_reuse`, a candidate node is rejected if it overlaps `[damage_start,
damage_end)`. This is the same overlap check `expand_for_tree` was performing to grow the
range — so any node `expand_for_tree` would have "captured" is already correctly rejected
by the cursor's own overlap test.

## Success Criteria

- `moon test` passes with same count as before (~368 tests, 0 failures)
- `moon check` clean
- No references to `adjust_tree_positions`, `expand_for_tree`, or `can_reuse_node` remain
  in source files (only in git history)
- `src/incremental/incremental_parser.mbt` is ~120 lines shorter
- `src/incremental/damage.mbt` loses `expand_for_tree` but keeps the rest intact
