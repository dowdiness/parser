# IncrementalParser Holdover Cleanup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove `adjust_tree_positions`, `expand_for_tree`, and the dead whole-tree reuse check from `IncrementalParser`, replacing them with a single direct `Range` construction from the edit.

**Architecture:** Pure deletion — no new logic. The `ReuseCursor` already handles damage overlap correctly, making the two O(n) AstNode walks and the whole-tree reuse check redundant. `self.syntax_tree` replaces `self.tree` as the initial-parse sentinel in `edit()`, making `self.tree` output-only.

**Tech Stack:** MoonBit (`moon check`, `moon test`, `moon info`, `moon fmt`)

---

### Task 1: Remove benchmark cases that call `expand_for_tree` and `adjust_tree_positions`

Remove these first so that removing the methods in later tasks doesn't break benchmarks.

**Files:**
- Modify: `src/benchmarks/benchmark.mbt`
- Modify: `src/benchmarks/performance_benchmark.mbt`

**Step 1: Simplify the "damage tracking" benchmark in `src/benchmarks/benchmark.mbt`**

The benchmark at lines 119–131 calls `expand_for_tree`. Replace it with a minimal `DamageTracker::new` benchmark (the only operation that survives the cleanup):

Current content to replace:
```moonbit
///|
/// Benchmark: Damage tracking
test "damage tracking" (b : @bench.T) {
  b.bench(fn() {
    let edit = @core.Edit::insert(4, 4)
    let damage = @incremental.DamageTracker::new(edit)
    let tree = @parse.parse_tree("λx.x") catch {
      _ => abort("benchmark failed")
    }
    damage.expand_for_tree(tree)
    b.keep(damage)
  })
}
```

Replace with:
```moonbit
///|
/// Benchmark: Damage tracking
test "damage tracking" (b : @bench.T) {
  b.bench(fn() {
    let edit = @core.Edit::insert(4, 4)
    let damage = @incremental.DamageTracker::new(edit)
    b.keep(damage)
  })
}
```

**Step 2: Remove three benchmark cases from `src/benchmarks/performance_benchmark.mbt`**

Remove the following three contiguous blocks (lines 136–175). They call `expand_for_tree` or `adjust_tree_positions` which will no longer exist:

```moonbit
///|
/// Benchmark: Damage tracking - localized damage
test "damage tracking - localized damage" (b : @bench.T) {
  b.bench(fn() {
    let edit = @core.Edit::replace(4, 5, 5)
    let damage = @incremental.DamageTracker::new(edit)
    let tree = @parse.parse_tree("x + 1") catch {
      _ => abort("benchmark failed")
    }
    damage.expand_for_tree(tree)
    b.keep(damage)
  })
}

///|
/// Benchmark: Damage tracking - widespread damage
test "damage tracking - widespread damage" (b : @bench.T) {
  b.bench(fn() {
    let edit = @core.Edit::replace(0, 1, 1)
    let damage = @incremental.DamageTracker::new(edit)
    let tree = @parse.parse_tree("λf.λx.if f x then x + 1 else x - 1") catch {
      _ => abort("benchmark failed")
    }
    damage.expand_for_tree(tree)
    b.keep(damage)
  })
}

///|
/// Benchmark: Position adjustment after edit
test "position adjustment after edit" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("λf.λx.f x")
    let tree = parser.parse()
    let edit = @core.Edit::insert(7, 4)
    let adjusted = parser.adjust_tree_positions(tree, edit)
    b.keep(adjusted)
  })
}
```

**Step 3: Verify `moon check` passes**

```bash
moon check 2>&1
```
Expected: clean output, no errors.

**Step 4: Commit**

```bash
git add src/benchmarks/benchmark.mbt src/benchmarks/performance_benchmark.mbt
git commit -m "chore(benchmarks): remove expand_for_tree and adjust_tree_positions benchmarks"
```

---

### Task 2: Remove `expand_for_tree` from `damage.mbt` and its test

**Files:**
- Modify: `src/incremental/damage.mbt`
- Modify: `src/incremental/damage_test.mbt`

**Step 1: Remove `expand_for_tree` from `src/incremental/damage.mbt`**

Remove the following method entirely (lines 107–138, starting at the `///|` doc comment):

```moonbit
///|
/// Expand damage for an entire tree
///
/// Wagner-Graham damage expansion:
/// Walk the tree and mark nodes that overlap damaged regions
pub fn DamageTracker::expand_for_tree(
  self : DamageTracker,
  tree : @ast.AstNode,
) -> Unit {
  // Check if this node overlaps any damaged range
  let node_range = @core.Range::new(tree.start, tree.end)
  let mut overlaps_damage = false
  for damaged in self.damaged_ranges {
    if damaged.overlaps(node_range) {
      overlaps_damage = true
      break
    }
  }
  if overlaps_damage {
    // This node overlaps damage, expand damage to include entire node
    self.add_range(node_range)

    // Recursively expand damage for children
    for child in tree.children {
      self.expand_for_tree(child)
    }
  } else {
    // Node doesn't overlap damage, but children might
    for child in tree.children {
      self.expand_for_tree(child)
    }
  }
}
```

**Step 2: Remove the `expand_for_tree` test from `src/incremental/damage_test.mbt`**

Remove the following test block (lines 64–77):

```moonbit
///|
test "DamageTracker::expand_for_tree" {
  let edit = @core.Edit::new(10, 5, 10)
  let tracker = DamageTracker::new(edit)

  // Create a simple tree by parsing
  let tree = @parse.parse_tree("1 + 2")
  tracker.expand_for_tree(tree)

  // Tree should be damaged (overlaps with edit range 10-20)
  // Since the tree spans 0-5, and edit is 10-20, they don't overlap
  // But if we adjust the test...
  inspect(tracker.damaged_ranges.length() > 0, content="true")
}
```

**Step 3: Run tests to confirm nothing broke**

```bash
moon test 2>&1 | tail -5
```
Expected: all tests pass (count will be 1 lower than before — the removed test was the only one).

**Step 4: Verify `moon check` is clean**

```bash
moon check 2>&1
```
Expected: no errors.

**Step 5: Commit**

```bash
git add src/incremental/damage.mbt src/incremental/damage_test.mbt
git commit -m "chore(incremental): remove DamageTracker::expand_for_tree — redundant with ReuseCursor"
```

---

### Task 3: Simplify `edit()`, remove `adjusted_tree` from `incremental_reparse`, delete dead methods

This is the main change. All edits are in one file.

**Files:**
- Modify: `src/incremental/incremental_parser.mbt`

**Step 1: Update the `tree` field comment in the struct (line 25)**

```moonbit
// BEFORE
  mut tree : @ast.AstNode? // Current parse tree

// AFTER
  mut tree : @ast.AstNode? // output-only: last parse result (never consumed as parse input)
```

**Step 2: Replace steps 2–5 in `edit()` (lines 157–178)**

Remove the `old_tree` binding, three numbered steps, and the `incremental_reparse` call with the old signature. Replace with a sentinel check on `syntax_tree` and a direct range computation:

```moonbit
// REMOVE this block (lines 157–178):
  // Step 2: Get old tree (if any)
  let old_tree = match self.tree {
    Some(t) => t
    None =>
      // No existing tree, do full parse
      return self.parse()
  }

  // Step 3: Adjust old tree positions based on edit
  let adjusted_tree = self.adjust_tree_positions(old_tree, edit)

  // Step 4: Identify damaged range using Wagner-Graham algorithm
  let damage = DamageTracker::new(edit)
  damage.expand_for_tree(adjusted_tree)

  // Step 5: Incremental reparse
  let damaged_range = damage.range()
  let new_tree = self.incremental_reparse(
    new_source, damaged_range, adjusted_tree, tokens,
  )
  self.tree = Some(new_tree)
  new_tree
```

Replace with:
```moonbit
  // Ensure initial parse has been done
  if self.syntax_tree.is_none() {
    return self.parse()
  }

  // Compute damaged range directly from edit
  let damaged_range = @core.Range::new(edit.start, edit.new_end())
  let new_tree = self.incremental_reparse(new_source, damaged_range, tokens)
  self.tree = Some(new_tree)
  new_tree
```

**Step 3: Remove `adjusted_tree` parameter from `incremental_reparse` and delete the whole-tree reuse check**

Current signature and opening block (lines 187–201):
```moonbit
fn IncrementalParser::incremental_reparse(
  self : IncrementalParser,
  source : String,
  damaged_range : @core.Range,
  adjusted_tree : @ast.AstNode,
  tokens : Array[@token.TokenInfo],
) -> @ast.AstNode {
  // Attempt whole-tree reuse: Can we reuse the entire tree?
  // Only safe if damage is completely outside tree bounds
  if self.can_reuse_node(adjusted_tree, damaged_range) &&
    adjusted_tree.start == 0 &&
    adjusted_tree.end == source.length() {
    // Tree is completely unchanged - reuse it
    return adjusted_tree
  }

  // Create cursor from old CST for subtree reuse
```

Replace with (remove `adjusted_tree` param and the entire `if` block):
```moonbit
fn IncrementalParser::incremental_reparse(
  self : IncrementalParser,
  source : String,
  damaged_range : @core.Range,
  tokens : Array[@token.TokenInfo],
) -> @ast.AstNode {
  // Create cursor from old CST for subtree reuse
```

**Step 4: Remove `can_reuse_node` method**

Remove this entire method (approximately lines 240–250):
```moonbit
///|
/// Check if a node can be reused (Wagner-Graham range check)
///
/// A node can be reused if it doesn't overlap with the damaged range.
/// Overlap occurs when: node.start < damaged.end AND node.end > damaged.start
fn IncrementalParser::can_reuse_node(
  _self : IncrementalParser,
  node : @ast.AstNode,
  damaged_range : @core.Range,
) -> Bool {
  // Node is reusable if it doesn't overlap the damaged range
  // No overlap means: node ends before damage starts OR node starts after damage ends
  node.end <= damaged_range.start || node.start >= damaged_range.end
}
```

**Step 5: Remove `adjust_tree_positions` method**

Remove this entire method (approximately lines 259–301):
```moonbit
///|
/// Adjust tree positions after an edit
///
/// Wagner-Graham position adjustment:
/// - Nodes before edit: unchanged
/// - Nodes overlapping edit: marked as damaged
/// - Nodes after edit: shifted by delta
pub fn IncrementalParser::adjust_tree_positions(
  self : IncrementalParser,
  tree : @ast.AstNode,
  edit : @core.Edit,
) -> @ast.AstNode {
  let delta = edit.delta()

  //  tree.end <= edit.start Doesn't Work!
  //  When tree.end == edit.start, the new content is inserted immediately adjacent to the tree. In lambda calculus grammar, adjacent terms form function application: (\x.x) 5 → App(Lam, Int).

  //  tree.end < edit.start means:
  //  - Only reuse the tree if there's a gap between the tree and the edit
  //  - If tree.end == edit.start (adjacent insertion), force a reparse to check for combinations
  if tree.end < edit.start {
    // Node is entirely before edit, no change needed
    tree
  } else if tree.start > edit.old_end() {
    // Node is entirely after edit, shift positions
    let adjusted_children = tree.children.map(fn(child) {
      self.adjust_tree_positions(child, edit)
    })
    @ast.AstNode::new(
      tree.kind,
      tree.start + delta,
      tree.end + delta,
      tree.node_id,
      adjusted_children,
    )
  } else {
    // Node overlaps edit range - will need reparsing
    // For now, just adjust children and mark range as needing update
    let adjusted_children = tree.children.map(fn(child) {
      self.adjust_tree_positions(child, edit)
    })
    @ast.AstNode::new(
      tree.kind,
      tree.start,
      tree.end,
      tree.node_id,
      adjusted_children,
    )
  }
}
```

**Step 6: Run `moon check`**

```bash
moon check 2>&1
```
Expected: clean, no errors. If you see "unknown identifier `can_reuse_node`" or similar, double-check steps 3–5 removed all call sites.

**Step 7: Run full test suite**

```bash
moon test 2>&1 | tail -5
```
Expected: all tests pass. Count will be lower by the `expand_for_tree` test removed in Task 2.

**Step 8: Confirm no stale references**

```bash
grep -rn "adjust_tree_positions\|can_reuse_node\|expand_for_tree" src/ 2>&1
```
Expected: no output (only historical entries in `pkg.generated.mbti` which will be regenerated next).

**Step 9: Commit**

```bash
git add src/incremental/incremental_parser.mbt
git commit -m "refactor(incremental): remove adjust_tree_positions + whole-tree reuse check

Damage range is now computed directly from Edit bounds. ReuseCursor
already handles per-node overlap checks, making the O(n) AstNode walks
redundant. self.syntax_tree replaces self.tree as the initial-parse
sentinel in edit(), making self.tree output-only.

Removes: adjust_tree_positions(), can_reuse_node(), the DamageTracker
walk in edit(), and the dead whole-tree reuse branch in incremental_reparse().
~120 lines deleted."
```

---

### Task 4: Update comments, regenerate interfaces, verify docs

**Files:**
- Modify: `src/incremental/incremental_parser.mbt`

**Step 1: Update the file header comment (lines 7–8)**

```moonbit
// BEFORE
// Strategy: Wagner-Graham damage tracking with whole-tree reuse
// or full reparse. Appropriate for recursive descent + small grammars.

// AFTER
// Strategy: Damage range derived from edit bounds; cursor-based subtree
// reuse via ReuseCursor. Appropriate for recursive descent + small grammars.
```

**Step 2: Update the `edit()` doc comment (approximately lines 106–111)**

```moonbit
// BEFORE
/// This implements the Wagner-Graham incremental parsing algorithm:
/// 1. Update source text
/// 2. Identify damaged region (edit range)
/// 3. Reparse damaged region, reusing whole tree where possible

// AFTER
/// Wagner-Graham incremental parsing:
/// 1. Update source text and token buffer
/// 2. Compute damaged range from edit bounds
/// 3. Reparse, reusing undamaged subtrees via ReuseCursor
```

**Step 3: Update the `incremental_reparse()` doc comment**

```moonbit
// BEFORE
/// Incremental reparse with Wagner-Graham approach and subtree reuse
///
/// Strategy:
/// 1. Attempt whole-tree reuse if damage is completely outside tree bounds
/// 2. Otherwise use cursor-based subtree reuse during parsing

// AFTER
/// Incremental reparse with cursor-based subtree reuse
///
/// Any CST node that does not overlap [damaged_range.start, damaged_range.end)
/// is a candidate for reuse by ReuseCursor.
```

**Step 4: Regenerate interfaces and format**

```bash
moon info && moon fmt
```
Expected: `src/incremental/pkg.generated.mbti` updated — `adjust_tree_positions` entry disappears.

**Step 5: Verify `pkg.generated.mbti` is clean**

```bash
grep "adjust_tree_positions\|can_reuse_node" src/incremental/pkg.generated.mbti
```
Expected: no output.

**Step 6: Run `bash check-docs.sh`**

```bash
bash check-docs.sh 2>&1
```
Expected: all checks pass.

**Step 7: Commit**

```bash
git add src/incremental/incremental_parser.mbt src/incremental/pkg.generated.mbti
git commit -m "docs(incremental): update comments after holdover cleanup; regenerate .mbti"
```

---

### Task 5: Archive plan files

**Files:**
- Modify: `docs/plans/2026-02-28-incremental-parser-cleanup-design.md`
- Modify: `docs/plans/2026-02-28-incremental-parser-cleanup.md` (this file)
- Move both to: `docs/archive/completed-phases/`
- Modify: `docs/README.md`

**Step 1: Mark both plan files complete**

In `docs/plans/2026-02-28-incremental-parser-cleanup-design.md`, change `**Status:** Approved` to `**Status:** Complete`.

In `docs/plans/2026-02-28-incremental-parser-cleanup.md` (this file), add `**Status:** Complete` after the `**Goal:**` line at the top.

**Step 2: Move both files to archive**

```bash
git mv docs/plans/2026-02-28-incremental-parser-cleanup-design.md docs/archive/completed-phases/
git mv docs/plans/2026-02-28-incremental-parser-cleanup.md docs/archive/completed-phases/
```

**Step 3: Update `docs/README.md`**

Remove from Active Plans:
```markdown
- [plans/2026-02-28-incremental-parser-cleanup-design.md](plans/2026-02-28-incremental-parser-cleanup-design.md) — remove `adjust_tree_positions` / `expand_for_tree` holdover
- [plans/2026-02-28-incremental-parser-cleanup.md](plans/2026-02-28-incremental-parser-cleanup.md) — implementation plan for IncrementalParser holdover cleanup
```

Restore Active Plans to:
```markdown
## Active Plans (Future Work)

_(none — see archive for completed plans)_
```

Add to Archive (Completed phase plans):
```markdown
- [archive/completed-phases/2026-02-28-incremental-parser-cleanup-design.md](archive/completed-phases/2026-02-28-incremental-parser-cleanup-design.md) — IncrementalParser holdover cleanup design
- [archive/completed-phases/2026-02-28-incremental-parser-cleanup.md](archive/completed-phases/2026-02-28-incremental-parser-cleanup.md) — IncrementalParser holdover cleanup implementation plan
```

**Step 4: Final verification**

```bash
moon test 2>&1 | tail -5
bash check-docs.sh 2>&1
```
Both must be clean.

**Step 5: Final commit**

```bash
git add docs/plans/ docs/archive/completed-phases/ docs/README.md
git commit -m "chore: archive IncrementalParser holdover cleanup plans after completion"
```
