# SyntaxNode-First Layer Design

**Date:** 2026-02-25
**Status:** Complete

## Problem

The `SyntaxNode` type in `seam/` is the right layer for all positioned tree operations — navigation, span queries, damage detection, and token access — but its API is too thin to do this job. As a result:

- `cst_convert.mbt` reaches through `.cst` directly with free functions (`extract_token_text`, `tight_span`, `collect_binary_ops`, `extract_error_text`)
- `incremental_parser.mbt` stores `CstNode?` and implements position logic (`adjust_tree_positions`, `can_reuse_node`) on `AstNode`
- `parse_tree_from_tokens` is a duplicate parser path that bypasses CST/SyntaxNode entirely
- `.cst` is a public field, so the abstraction boundary is unenforced

## Guiding Principle

> Work on `SyntaxNode` for all tree operations. Touch `CstNode` only when you need lossless concrete syntax. Touch `AstNode` only when you need semantics (types, evaluation, JSON output).

## Phased Plan

### Phase 1 — Extend `SyntaxNode` in `seam/` (this document)

Add the methods `SyntaxNode` needs to replace all direct `.cst` access. No other files change.

### Phase 2 — Approach B: SyntaxNode-first layer ✅ Complete

- Replace direct `.cst` access in `cst_convert.mbt` with SyntaxNode methods ✅
- Remove duplicate `parse_tree_from_tokens` ✅
- `IncrementalParser` stores `SyntaxNode?` instead of `CstNode?` ✅
- Make `.cst` private (closes Phase 2) ✅
- `parse_with_error_recovery_tokens` removed post-review (no callers; implementation
  was broken — passed `""` as source to `parse_cst_recover_with_tokens`, causing
  `text_at()` to return `""` for every token) ✅
- `adjust_tree_positions` / `can_reuse_node` intentionally left on `AstNode` —
  these operate on the semantic tree layer, not the CST/SyntaxNode layer, so
  migrating them was descoped

### Phase 3 — Approach C: Typed SyntaxNode views (future)

Typed wrappers: `LambdaExpr(SyntaxNode)`, `AppExpr(SyntaxNode)`, etc.
`AstNode` becomes JSON-serialization-only.

---

## Phase 1 Specification

### New type: `SyntaxToken`

The positioned counterpart to `CstToken`, mirroring how `SyntaxNode` wraps `CstNode`.

```
struct SyntaxToken {
  cst    : CstToken
  offset : Int
}

fn SyntaxToken::start(Self) -> Int       // = offset
fn SyntaxToken::end(Self) -> Int         // = offset + cst.text_len()
fn SyntaxToken::kind(Self) -> RawKind    // = cst.kind
fn SyntaxToken::text(Self) -> String     // = cst.text
impl Show  for SyntaxToken               // "IdentToken@[3,6)"
impl Debug for SyntaxToken               // "SyntaxToken { kind: IdentToken, offset: 3, text: \"foo\" }"
```

### New methods on `SyntaxNode`

**Token iteration** (what `children()` currently skips):

```
fn SyntaxNode::all_children(Self) -> Array[SyntaxElement]
fn SyntaxNode::tokens(Self) -> Array[SyntaxToken]
```

`SyntaxElement` is the positioned union of a child node or token:

```
enum SyntaxElement {
  Node(SyntaxNode)
  Token(SyntaxToken)
}
```

**Targeted token lookup** (replaces `extract_token_text`, `collect_binary_ops`):

```
fn SyntaxNode::find_token(Self, RawKind) -> SyntaxToken?
fn SyntaxNode::tokens_of_kind(Self, RawKind) -> Array[SyntaxToken]
```

**Span helper** (replaces `tight_span` free function):

```
fn SyntaxNode::tight_span(Self) -> (Int, Int)
```

Skips leading/trailing whitespace tokens. No manual offset threading needed since `SyntaxNode` already carries its offset.

**Position query** (for damage detection and editor queries):

```
fn SyntaxNode::find_at(Self, Int) -> SyntaxNode
```

Returns the deepest descendant whose span contains the offset. Falls back to `self` if no child matches. Standard "smallest enclosing node" semantic (same as tree-sitter and rowan).

**Traits on `SyntaxNode`:**

```
impl Show  for SyntaxNode   // "LambdaExpr@[3,10)"
impl Debug for SyntaxNode   // "SyntaxNode { kind: LambdaExpr, offset: 3, text_len: 7 }"
```

### What does NOT change in Phase 1

- `.cst` field stays public (Phase 2 makes it private)
- No changes to `cst_convert.mbt`, `incremental_parser.mbt`, `parser.mbt`, or any consumer package
- `AstNode` public API unchanged

### Files changed in Phase 1

- `seam/syntax_node.mbt` — add `SyntaxToken`, `SyntaxElement`, new methods
- `seam/syntax_node_wbtest.mbt` — tests for all new methods
- `seam/pkg.generated.mbti` — updated by `moon info`
