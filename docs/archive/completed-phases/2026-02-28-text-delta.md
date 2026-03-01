# TextDelta Adapter Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `TextDelta (Retain | Insert | Delete)` and `to_edits(Array[TextDelta]) -> Array[Edit]` to `src/core/`, bridging the Quill/Loro delta format to the incremental parser.

**Architecture:** Two new files in the existing `src/core/` package — `delta.mbt` (enum + function) and `delta_test.mbt` (tests). No new package, no changes to `IncrementalParser`. The returned `Array[Edit]` is in sequential-application order: each `Edit.start` is already adjusted for all prior edits, so the caller can `for edit in to_edits(delta) { parser.edit(edit, updated_source) }` without further position math.

**Tech Stack:** MoonBit (`moon test -p dowdiness/parser/src/core`, `moon check`)

---

### Task 1: Implement `TextDelta` and `to_edits`

**Files:**
- Create: `src/core/delta.mbt`
- Create: `src/core/delta_test.mbt`

**Step 1: Write failing tests in `src/core/delta_test.mbt`**

```moonbit
///|
test "to_edits: empty" {
  let result = to_edits([])
  inspect(result.length(), content="0")
}

///|
test "to_edits: retain only produces no edits" {
  let result = to_edits([TextDelta::Retain(10)])
  inspect(result.length(), content="0")
}

///|
test "to_edits: pure insert at start" {
  let result = to_edits([TextDelta::Insert("hi")])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="0")
  inspect(result[0].new_len, content="2")
}

///|
test "to_edits: insert after retain" {
  let result = to_edits([TextDelta::Retain(5), TextDelta::Insert("hi")])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="5")
  inspect(result[0].old_len, content="0")
  inspect(result[0].new_len, content="2")
}

///|
test "to_edits: delete after retain" {
  let result = to_edits([TextDelta::Retain(3), TextDelta::Delete(4)])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="3")
  inspect(result[0].old_len, content="4")
  inspect(result[0].new_len, content="0")
}

///|
test "to_edits: delete+insert merges into replace" {
  // The common CRDT case: [Retain(5), Delete(3), Insert("hi")] → one Edit
  let result = to_edits([
    TextDelta::Retain(5),
    TextDelta::Delete(3),
    TextDelta::Insert("hi"),
  ])
  inspect(result.length(), content="1")
  inspect(result[0].start, content="5")
  inspect(result[0].old_len, content="3")
  inspect(result[0].new_len, content="2")
}

///|
test "to_edits: multi-op adjusts positions sequentially" {
  // [Retain(3), Delete(2), Retain(4), Insert("x")]
  // Edit 1: delete 2 at position 3, no Insert follows → Edit { start: 3, old_len: 2, new_len: 0 }
  // accumulated_delta = -2; cursor_orig = 5
  // Retain(4): cursor_orig = 9
  // Edit 2: insert at position 9 + (-2) = 7 → Edit { start: 7, old_len: 0, new_len: 1 }
  let result = to_edits([
    TextDelta::Retain(3),
    TextDelta::Delete(2),
    TextDelta::Retain(4),
    TextDelta::Insert("x"),
  ])
  inspect(result.length(), content="2")
  inspect(result[0].start, content="3")
  inspect(result[0].old_len, content="2")
  inspect(result[0].new_len, content="0")
  inspect(result[1].start, content="7")
  inspect(result[1].old_len, content="0")
  inspect(result[1].new_len, content="1")
}

///|
test "to_edits: insert then delete — no merge, positions adjusted" {
  // [Insert("x"), Delete(2)] — Insert comes first, Delete does not merge
  // Insert("x"): emit Edit { start: 0, old_len: 0, new_len: 1 }, accumulated_delta = 1
  // Delete(2): emit Edit { start: 0 + 1 = 1, old_len: 2, new_len: 0 }
  let result = to_edits([TextDelta::Insert("x"), TextDelta::Delete(2)])
  inspect(result.length(), content="2")
  inspect(result[0].start, content="0")
  inspect(result[0].old_len, content="0")
  inspect(result[0].new_len, content="1")
  inspect(result[1].start, content="1")
  inspect(result[1].old_len, content="2")
  inspect(result[1].new_len, content="0")
}
```

**Step 2: Run tests to verify they fail**

```bash
moon test -p dowdiness/parser/src/core -f delta_test.mbt 2>&1
```
Expected: compilation error — `TextDelta` and `to_edits` do not exist yet.

**Step 3: Implement `src/core/delta.mbt`**

```moonbit
///|
pub(all) enum TextDelta {
  Retain(Int)    // advance cursor n bytes — no edit emitted
  Insert(String) // insert text at cursor position
  Delete(Int)    // delete n bytes at cursor position
} derive(Show, Eq)

///|
/// Convert a TextDelta sequence to Edits for IncrementalParser.
///
/// The returned Edits are in sequential-application order: each Edit's start
/// is in the coordinate space after all previous Edits have been applied.
/// The caller can iterate and call `parser.edit(edit, updated_source)` for each
/// without additional position adjustment.
///
/// Adjacent Delete+Insert are merged into a single replace Edit — the common
/// CRDT pattern [Retain(n), Delete(m), Insert(s)] produces exactly one Edit.
pub fn to_edits(deltas : Array[TextDelta]) -> Array[Edit] {
  let result : Array[Edit] = []
  let mut cursor_orig = 0    // position in original document
  let mut accumulated_delta = 0  // net offset shift from emitted edits
  let mut i = 0
  while i < deltas.length() {
    match deltas[i] {
      Retain(n) => {
        cursor_orig += n
        i += 1
      }
      Delete(n) => {
        let pos = cursor_orig + accumulated_delta
        // Merge Delete+Insert into a replace Edit when adjacent
        if i + 1 < deltas.length() {
          match deltas[i + 1] {
            Insert(s) => {
              result.push(Edit::new(pos, n, s.length()))
              accumulated_delta += s.length() - n
              cursor_orig += n
              i += 2  // consume both Delete and Insert
            }
            _ => {
              result.push(Edit::new(pos, n, 0))
              accumulated_delta -= n
              cursor_orig += n
              i += 1
            }
          }
        } else {
          result.push(Edit::new(pos, n, 0))
          accumulated_delta -= n
          cursor_orig += n
          i += 1
        }
      }
      Insert(s) => {
        result.push(Edit::new(cursor_orig + accumulated_delta, 0, s.length()))
        accumulated_delta += s.length()
        // cursor_orig unchanged — Insert consumes no original chars
        i += 1
      }
    }
  }
  result
}
```

**Step 4: Run tests to verify they pass**

```bash
moon test -p dowdiness/parser/src/core -f delta_test.mbt 2>&1
```
Expected: all 8 new tests pass.

**Step 5: Run full suite**

```bash
moon test 2>&1 | tail -5
```
Expected: same passing count + 8 new tests, 0 failures.

**Step 6: Commit**

```bash
git add src/core/delta.mbt src/core/delta_test.mbt
git commit -m "feat: add TextDelta enum and to_edits adapter in src/core"
```

---

### Task 2: Regenerate interfaces, update docs, archive plan

**Files:**
- Auto-updated: `src/core/pkg.generated.mbti` and dependent `.mbti` files
- Modify: `docs/plans/2026-02-28-text-delta-design.md`
- Modify: `docs/README.md`

**Step 1: Regenerate interfaces and format**

```bash
moon info && moon fmt
```

**Step 2: Verify clean**

```bash
moon check 2>&1
bash check-docs.sh 2>&1
```
Both must be clean.

**Step 3: Confirm `TextDelta` appears in the generated interface**

```bash
grep TextDelta src/core/pkg.generated.mbti
```
Expected: the `TextDelta` enum and `to_edits` function appear in the output.

**Step 4: Mark design doc complete and archive**

In `docs/plans/2026-02-28-text-delta-design.md`, change `**Status:** Approved` to `**Status:** Complete`.

```bash
git mv docs/plans/2026-02-28-text-delta-design.md docs/archive/completed-phases/
```

**Step 5: Update `docs/README.md`**

Remove from Active Plans:
```markdown
- [plans/2026-02-28-text-delta-design.md](plans/2026-02-28-text-delta-design.md) — design for TextDelta → Edit adapter
```

The archive section already links to `archive/completed-phases/` — no line-level change needed there.

**Step 6: Run `bash check-docs.sh`**

```bash
bash check-docs.sh 2>&1
```
Expected: all checks pass.

**Step 7: Final commit**

```bash
git add docs/ src/core/pkg.generated.mbti
git commit -m "chore: regenerate interfaces and archive text-delta plan"
```
