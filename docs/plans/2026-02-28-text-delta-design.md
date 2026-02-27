# Design: TextDelta Adapter

**Created:** 2026-02-28
**Status:** Approved

## Problem

The CRDT layer (`event-graph-walker`) and external editors express text changes as
Quill/Loro-style `TextDelta` sequences (`Retain | Insert | Delete`). The incremental
parser accepts `Edit { start, old_len, new_len }`. There is no conversion between them.

The ADR `docs/decisions/2026-02-28-edit-lengths-not-endpoints.md` already names this
as the planned bridge:

```
TextDelta (Retain | Insert | Delete)   ← Loro/Quill pattern
  ↓ .to_edits()
Edit { start, old_len, new_len }       ← parser's Editable primitive
  ↓
IncrementalParser
```

## Decision

Add `TextDelta` enum and `to_edits()` function to `src/core/` (new file `delta.mbt`).
No new package. `IncrementalParser` is unchanged.

## Data Types

```moonbit
pub(all) enum TextDelta {
  Retain(Int)    // advance cursor n bytes — no edit emitted
  Insert(String) // insert text at cursor
  Delete(Int)    // delete n bytes at cursor
}

pub fn to_edits(deltas : Array[TextDelta]) -> Array[Edit]
```

`Insert` carries the actual string so callers can reconstruct the new source text if
needed, and so `new_len` is always `s.length()` without requiring a separate argument.

## Algorithm

`to_edits` walks `deltas` left-to-right with two state variables:

- `cursor_orig : Int` — position in the **original** document (advances on `Retain` and `Delete`)
- `accumulated_delta : Int` — net length change from all edits already emitted

The `Edit.start` for each new edit is `cursor_orig + accumulated_delta` — the location in
the document after all previous edits have been applied. This means the returned `Array[Edit]`
can be applied sequentially without additional position adjustment by the caller.

```
Retain(n):
  cursor_orig += n

Delete(n) immediately followed by Insert(s)  ← merge into replace
  emit Edit { start: cursor_orig + accumulated_delta, old_len: n, new_len: s.length() }
  accumulated_delta += s.length() - n
  cursor_orig += n
  skip Insert (consumed)

Delete(n)  ← standalone delete
  emit Edit { start: cursor_orig + accumulated_delta, old_len: n, new_len: 0 }
  accumulated_delta -= n
  cursor_orig += n

Insert(s)  ← standalone insert (not consumed by merge)
  emit Edit { start: cursor_orig + accumulated_delta, old_len: 0, new_len: s.length() }
  accumulated_delta += s.length()
  (cursor_orig unchanged — no original chars consumed)
```

The merge in the `Delete + Insert` case is the critical optimisation: the overwhelmingly
common CRDT pattern `[Retain(n), Delete(m), Insert(text)]` produces **one** `Edit` instead
of two, letting the caller call `parser.edit()` once.

## Usage

```moonbit
let delta = [TextDelta::Retain(5), TextDelta::Delete(3), TextDelta::Insert("hello")]
let edits = to_edits(delta)
// edits == [Edit { start: 5, old_len: 3, new_len: 5 }]

for edit in edits {
  parser.edit(edit, updated_source)
}
```

## What Does NOT Change

- `Edit`, `Editable`, `Range`, `ReuseSlot` — untouched
- `IncrementalParser.edit()` — still takes a single `Edit`
- `src/core/moon.pkg` — no new imports (delta.mbt only uses `Edit` from the same package)
- All existing tests

## File Footprint

| File | Change |
|------|--------|
| `src/core/delta.mbt` | New — `TextDelta` enum + `to_edits` function |
| `src/core/delta_test.mbt` | New — unit tests |
| `src/core/lib.mbt` or `src/core/moon.pkg` | Verify `TextDelta` is re-exported if needed |

## Success Criteria

- `moon test` passes (existing 368 tests + new delta tests)
- `moon check` clean
- `to_edits([Retain(5), Delete(3), Insert("hi")])` → single `Edit { start: 5, old_len: 3, new_len: 2 }`
- `to_edits([Retain(3), Delete(2), Retain(4), Insert("x")])` → two Edits with sequentially-adjusted positions
- Empty array → empty array
- `to_edits` is accessible from the root facade (`src/lib.mbt` or caller packages)
