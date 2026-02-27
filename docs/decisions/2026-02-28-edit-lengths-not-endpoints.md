# ADR: Store Edit as Lengths, Not Endpoints

**Date:** 2026-02-28
**Status:** Accepted

## tl;dr

- Context: `Edit` stored `{start, old_end, new_end}` — endpoints derived by adding `start` to each length.
- Decision: Store `{start, old_len, new_len}` — lengths as primitives. Expose `old_end()` and `new_end()` as computed getters.
- Rationale: Lengths are the natural primitive in every major incremental text-processing library. Endpoints are derived values.
- Consequences: `Edit::new(start, old_len, new_len)` replaces the old endpoint-based constructor. Call sites using `.old_end`/`.new_end` as fields migrate to method calls.

---

## What the ecosystem does

Every major incremental text-processing library stores lengths, not endpoints:

### tree-sitter — `TSInputEdit`

```c
typedef struct {
  uint32_t start_byte;
  uint32_t old_end_byte;   // start_byte + old_text.len()
  uint32_t new_end_byte;   // start_byte + new_text.len()
} TSInputEdit;
```

tree-sitter stores endpoints here, but the API explicitly documents them as
`start_byte + length`. The tree-sitter documentation notes that `old_end_byte`
and `new_end_byte` are derived from the text lengths — callers compute them
from the text they have. In practice most wrappers pass `start + old_len` and
`start + new_len` directly.

### LSP — `TextDocumentContentChangeEvent`

```json
{
  "range": { "start": {...}, "end": {...} },
  "text": "new content"
}
```

LSP passes the replacement text itself, so `new_len` is `text.length()`.
The range end is computed by the client. The length of what is deleted is
`old_end - start` — endpoints first, but only because LSP's range type is
designed for human-readable line/column positions, not byte offsets.

### Loro — `TextDelta` (Retain | Insert | Delete)

```
type TextDelta =
  | Retain(usize)
  | Insert { insert: String }
  | Delete(usize)
```

Loro's `TextDelta` (following Quill's Delta format) uses **pure lengths** —
there are no positions at all. A sequence of deltas is applied left-to-right;
each operation implicitly carries a cursor that advances by the operand length.
To convert a single `TextEdit { start, old_len, new_len }` to `TextDelta`:

```
[Retain(start), Delete(old_len), Insert(new_text)]
```

This conversion is only natural when `Edit` stores lengths. With endpoints
you would need `Delete(old_end - start)` — a subtraction that obscures intent.

### diamond-types — `PositionalComponent`

```rust
pub enum PositionalComponent {
  Ins { len: usize, content_known: bool },
  Del(usize),   // length deleted
}
pub struct PositionalOp {
  pub components: SmallVec<[PositionalComponent; 2]>,
}
```

diamond-types (the Rust reference implementation for the eg-walker algorithm
this project uses) stores lengths throughout. Positions are tracked separately
in `KVPair<PositionalOp>` wrapper types. The CRDT layer never works with
absolute endpoints — it operates on lengths and applies them to a cursor.

---

## Why lengths are the primitive

**Lengths compose; endpoints do not.**

Two edits `[Delete(3), Insert(5)]` can be summed: total deletion = 3, total
insertion = 5. Two endpoint pairs `[(0,3), (0+delta, 0+delta+5)]` require
knowing the running cursor position before you can combine them.

**Lengths survive reordering; endpoints do not.**

In OT and CRDT algorithms, operations from different peers arrive in
non-causal order. A length-based operation `Delete(3)` retains its meaning
regardless of what precedes it (position transforms handle the start). An
endpoint-based operation `Delete(0, 3)` has an absolute start that must be
transformed first.

**The `start` field is already a position; everything else should be a length.**

`Edit { start, old_len, new_len }` reads as: "beginning at `start`, remove
`old_len` bytes and insert `new_len` bytes." The start is the only point of
contact with the document's coordinate space. Once anchored, everything else
is relative — a length.

---

## The `Editable` trait

The session also introduced `pub trait Editable`:

```moonbit
pub trait Editable {
  start(Self)   -> Int
  old_len(Self) -> Int
  new_len(Self) -> Int
}
```

This defines the **three primitives** that describe any atomic text edit.
The trait exists as the foundation for the pipeline shown in the eg-walker
paper:

```
TextDelta (Retain | Insert | Delete)     [Loro/Quill pattern — future]
  ↓ .to_edits()
TextEdit { start, old_len, new_len }     ← Edit struct
  ↓ implements
pub trait Editable                       ← this trait
  ↓
IncrementalParser
```

When a `to_edits()` conversion is added to `TextDelta`, `IncrementalParser`
can accept any `T : Editable` instead of the concrete `Edit` type. The struct
fields and the trait method names are intentionally identical so that `Edit`'s
impl is trivial direct field access — no translation layer.

---

## MoonBit notes

**One `pub impl` per method.** Unlike Rust or Swift (single `impl` block),
MoonBit requires a separate declaration per trait method:

```moonbit
pub impl Editable for Edit with start(self)   { self.start   }
pub impl Editable for Edit with old_len(self) { self.old_len }
pub impl Editable for Edit with new_len(self) { self.new_len }
```

Each method is a first-class declaration in the `.mbti` interface file,
individually visible in documentation and IDE tooling.

**Computed getters are zero-cost.** `Edit::old_end` and `Edit::new_end` are
regular methods whose bodies are `self.start + self.old_len` / `self.new_len`.
MoonBit's compiler inlines these. Migrating field accesses to method calls
(`edit.old_end` → `edit.old_end()`) is the only source-level change required
at call sites.

**`moon fmt` reformats one-liners.** The user wrote compact single-line impls;
`moon fmt` expanded them to multi-line blocks with `///|` separators. This is
idiomatic MoonBit style — each public item gets its own documentation anchor.
