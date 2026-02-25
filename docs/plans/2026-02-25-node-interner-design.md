# NodeInterner Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:writing-plans to create the implementation plan.

**Goal:** Add `NodeInterner` to `seam/` to deduplicate `CstNode` objects by structural identity, giving identical subtrees a single shared heap reference.

**Architecture:** Standalone struct parallel to `Interner` (which deduplicates `CstToken`). Document-scoped, owned by `IncrementalParser` alongside `Interner`. New `build_tree_fully_interned` wires both interners together. Parser functions accept `node_interner?` as optional labelled arg matching the existing `interner?` pattern.

**Tech Stack:** MoonBit, `@hashmap.HashMap`, `seam` package, `src/incremental` package.

---

## NodeInterner API (`seam/node_interner.mbt`)

```moonbit
pub struct NodeInterner {
  priv nodes : @hashmap.HashMap[CstNode, CstNode]
}

pub fn NodeInterner::new() -> NodeInterner
pub fn NodeInterner::intern_node(self : NodeInterner, node : CstNode) -> CstNode
pub fn NodeInterner::size(self : NodeInterner) -> Int
pub fn NodeInterner::clear(self : NodeInterner) -> Unit
```

`HashMap[CstNode, CstNode]` (key == value): `get(node)` uses `CstNode::Hash` (cached O(1)) then `CstNode::Eq` (hash fast-reject, structural check only on collision). MoonBit's hashmap handles collision chains. On hit returns canonical reference; on miss stores and returns the new node.

Tree construction is bottom-up, so by the time a parent is interned, all children are already canonical — parent equality checks terminate at hash match without deep recursion.

## `build_tree_fully_interned` (`seam/event.mbt`)

New function and `EventBuffer` wrapper. At each `FinishNode`:

```moonbit
let node = CstNode::new(kind, children, trivia_kind~)
let interned = node_interner.intern_node(node)
// push interned to parent children
```

Existing `build_tree` and `build_tree_interned` unchanged.

## Parser integration (`src/parser/cst_parser.mbt`)

`parse_cst_recover` and `parse_cst_recover_with_tokens` gain:

```moonbit
node_interner? : @seam.NodeInterner? = None
```

When `Some`, uses `build_tree_fully_interned`. When `None`, existing behaviour unchanged — no breakage for other callers.

## IncrementalParser (`src/incremental/incremental_parser.mbt`)

New field:

```moonbit
priv node_interner : @seam.NodeInterner
```

- `::new()` initialises `node_interner: @seam.NodeInterner::new()`
- `parse()` and `edit()` pass `node_interner=Some(self.node_interner)`
- `interner_clear()` calls `self.node_interner.clear()` alongside `self.interner.clear()`
- New `node_interner_size() -> Int` mirrors `interner_size()` for diagnostics and tests
- Doc comment gains: "the `node_interner` accumulates one entry per distinct structural subtree ever seen, bounded by the document's subtree vocabulary"

## Testing (`seam/node_interner_wbtest.mbt`)

Unit tests:
- `intern_node` returns structurally equal node on first call
- Second call for identical structure: returns cached node, `size()` stays 1
- Two distinct structures: `size()` grows to 2
- `clear()` resets `size()` to 0; fresh intern after clear works
- Parent whose children were already interned interns correctly (bottom-up invariant)

Integration tests in `src/incremental/`:
- After `parse()`, `node_interner_size()` is positive
- After `interner_clear()`, both `interner_size()` and `node_interner_size()` return 0
- Parsing same source twice: `node_interner_size()` does not grow on second parse

## Trade-offs accepted

Same as `Interner`: unbounded growth within a document session (bounded by structural vocabulary), deleted subtrees stay live until `clear()`. Cross-document reuse requires calling `interner_clear()` between documents.
