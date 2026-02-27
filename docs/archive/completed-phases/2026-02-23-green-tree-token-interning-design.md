# Green Tree Token Interning — Design

**Date:** 2026-02-23
**Status:** Approved
**Scope:** `green-tree` public API + `IncrementalParser` integration

---

## Goal

Add token interning to the green tree: deduplicate `GreenToken` objects so that
identical `(kind, text)` pairs always resolve to the same heap object. This
delivers two benefits simultaneously:

1. **Memory savings** — `x` appearing 100 times in a document allocates one
   `GreenToken`, not 100.
2. **O(1) pointer equality** — code that exclusively creates tokens through an
   `Interner` may use `physical_equal` instead of structural `==`, since
   structural equality implies pointer equality for interned tokens.

Node-level interning (`GreenNode`) is deferred. The `Interner` type is
structured to accept a node table in a follow-on change with no API breakage.

---

## Decisions

| Question | Decision |
|---|---|
| Goal | Canonical form: deduplication + pointer equality |
| Scope | Per-parse session (owned by `IncrementalParser`) |
| Granularity | Tokens first, nodes deferred |
| Target | Exported from `green-tree`; used by `IncrementalParser` |
| Constructor style | User-defined constructors (`Interner()`, not `Interner::new()`) |

---

## Architecture

### `Interner` type

```moonbit
pub struct Interner {
  priv tokens : HashMap[(RawKind, String), GreenToken]
}

pub fn Interner() -> Interner
pub fn Interner::intern_token(self, kind : RawKind, text : String) -> GreenToken
pub fn Interner::size(self) -> Int
pub fn Interner::clear(self) -> Unit
```

The intern table keys by `(RawKind, String)` rather than by the precomputed
`Int` hash. The `Int` hash is 32-bit FNV-1a; distinct tokens can share a hash
value. Keying by content guarantees that `intern_token` always returns the
structurally correct token. The map's own internal hashing handles bucket
distribution.

`intern_token` algorithm:
1. Look up `(kind, text)` in the table.
2. Hit → return the stored `GreenToken` reference (same heap object as before).
3. Miss → call `GreenToken::new(kind, text)`, store it, return it.

`size` returns the number of distinct interned tokens (for diagnostics and
tests). `clear` flushes the table, allowing an `Interner` to be reused across
independent documents without a fresh allocation.

### `build_tree_interned`

A new sibling to `build_tree`, added to `green-tree`:

```moonbit
pub fn build_tree_interned(
  events    : Array[ParseEvent],
  root_kind : RawKind,
  interner  : Interner,
) -> GreenNode
```

Identical to `build_tree` except the `Token(kind, text)` branch calls
`interner.intern_token(kind, text)` instead of `GreenToken::new(kind, text)`.
The existing `build_tree` is untouched — zero breaking changes.

### Ownership and lifetime

`IncrementalParser` owns one `Interner` for its entire session:

```moonbit
pub struct IncrementalParser {
  // ... existing fields ...
  interner : Interner   // created in IncrementalParser() constructor
}
```

The interner persists across re-parses of the same document, so `x` from parse
N and `x` from parse N+1 are the same `GreenToken` object. When the parser is
dropped, the GC collects the interner and all tokens it holds.

The `ReuseCursor` path (Phase 4 subtree reuse) is unaffected — it bypasses
`build_tree` entirely and returns old `GreenNode` references directly. Tokens
in those reused nodes are already interned from a prior parse.

---

## API Contract

### Exported from `green-tree`

| Symbol | Notes |
|---|---|
| `pub struct Interner` | Fields private (opaque) |
| `pub fn Interner()` | User-defined constructor |
| `pub fn Interner::intern_token` | Core interning operation |
| `pub fn Interner::size` | Diagnostic / test helper |
| `pub fn Interner::clear` | Optional flush for multi-document reuse |
| `pub fn build_tree_interned` | Interning-aware tree builder |

### Stability guarantees

- `Eq` and `Hash` on `GreenToken` are **unchanged** — structural, not
  pointer-based.
- Pointer equality (`physical_equal`) is valid for any two `GreenToken` values
  produced through the **same `Interner` instance**. This is a documented
  behavioural guarantee, not a type-level invariant.
- `build_tree` remains available and unmodified.

### Pointer equality — MoonBit target notes

In MoonBit's wasm-gc, native, and js targets, `struct` values are heap-
allocated reference types. `physical_equal` (from `moonbitlang/core`) correctly
tests object identity on all current targets. The guarantee holds for the
lifetime of the `Interner` that produced the tokens.

### Concurrency

`Interner` is not thread-safe. MoonBit does not yet have stable multi-threading
on wasm-gc. One interner per parser session, one thread per session, is the
expected and documented usage.

---

## Deferred: Node Interning

`GreenNode` interning is not included in this iteration. When added, the
`Interner` struct gains a second field:

```moonbit
pub struct Interner {
  priv tokens : HashMap[(RawKind, String), GreenToken]
  priv nodes  : HashMap[Int, Array[GreenNode]]   // hash → collision chain
}
```

Node interning keys by the existing cached `GreenNode::hash` (structural hash)
with equality verification on collision. The lookup integrates into
`build_tree_interned` after each `FinishNode` event. No public API change is
needed — `build_tree_interned` and `Interner::intern_token` remain the same
signatures.

---

## Testing

### Unit tests — `green-tree` (whitebox)

| Test | Assertion |
|---|---|
| `intern_token` same `(kind, text)` twice | `physical_equal(a, b)` |
| `intern_token` different `(kind, text)` | `not(physical_equal(a, b))` |
| `size` increments only on miss | size == distinct pairs |
| `build_tree_interned` == `build_tree` structurally | `tree_a == tree_b` |
| All tokens in interned tree with same `(kind, text)` | `physical_equal` each pair |

### Integration tests — `parser` (blackbox)

| Test | Assertion |
|---|---|
| `IncrementalParser` with interning == without interning | structural equality |
| Re-parse of identical source — shared tokens | `physical_equal` across generations |
| `size` after N parses of same expression | bounded by vocabulary, not N × tokens |

### Property test

For any random source string and random edit sequence, `build_tree_interned`
produces a structurally equal tree to `build_tree` on the same event stream.
Extends the existing differential oracle.

---

## Non-Goals

- Global / process-wide intern table (lifetime and GC complexity outweighs
  benefit for a published library without weak-reference support).
- Thread safety.
- Changing `Eq` semantics on `GreenToken` or `GreenNode`.
- Node-level interning (deferred to follow-on iteration).
