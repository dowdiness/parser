# Generic Incremental Reuse Design

**Date:** 2026-02-24
**Status:** Proposed
**Goal:** Move `ReuseCursor` into `core` as a generic `ReuseCursor[T, K]`, integrate it transparently into `ParserContext` via a `node()` combinator, so any language built on the framework gets incremental subtree reuse for free.

---

## Motivation

`ReuseCursor` currently lives in `src/parser/` and is hardcoded for Lambda Calculus — it references `@syntax.SyntaxKind`, `@token.Token`, and `@token.TokenInfo` directly. The `parse_green_with_cursor` and `parse_green_recover_with_tokens` entry points accept a cursor parameter but ignore it (`_cursor`), making incremental parsing a no-op.

The generic `ParserContext[T, K]` migration (2026-02-23) established the framework. This design completes it by making reuse generic and transparent to grammar authors.

---

## Design Principles

1. **Transparent by default** — grammar authors get reuse without thinking about it
2. **Opt-out by configuration** — raw `start_node`/`finish_node` bypasses reuse
3. **Zero overhead without cursor** — when `reuse_cursor` is `None`, no reuse checks run
4. **Dictionary passing for language-specific behavior** — `LanguageSpec` closures, not traits (MoonBit's orphan rule prevents cross-package trait impl)
5. **`Eq` trait bound where safe** — replaces `tokens_equal` closure (builtin, already derived)

---

## Why Dictionary Passing, Not Traits

MoonBit enforces: only the trait's package or the type's package can write `impl Trait for Type`. Our architecture has three packages:

```
core   — defines the framework (traits would live here)
token  — defines Token enum (leaf package, no deps)
parser — uses both (would want to write impls here)
```

Traits would force either `token` → `core` dependency (pollutes a leaf package) or impls in `core` (circular). Dictionary passing (`LanguageSpec` record of closures) avoids this entirely.

Builtin trait bounds (`Eq`, `Show`) are safe — `Token` and `SyntaxKind` already derive them.

Theoretically: `LanguageSpec` is dictionary passing (type-level constraint → record of functions). If profiling ever shows closure indirection matters in a hot loop, we can defunctionalize specific callbacks into tagged enums + apply. For now, dictionary passing is the correct abstraction level — the framework needs runtime flexibility for different languages.

---

## Grammar API: The `node()` Combinator

### The Problem

In an imperative parser, `start_node(kind)` is called inside the grammar function body. To skip the body on reuse, the framework must not execute it. But `start_node` cannot unwind its caller.

### The Solution

Wrap the body in a closure. The framework decides whether to call it:

```moonbit
pub fn[T : Eq, K] ParserContext::node(
  self : ParserContext[T, K],
  kind : K,
  body : () -> Unit,
) -> Unit {
  match self.try_reuse(kind) {
    Some(reused) => self.emit_reused(reused)  // skip body entirely
    None => {
      self.start_node(kind)
      body()
      self.finish_node()
    }
  }
}
```

When `reuse_cursor` is `None`, `try_reuse` returns `None` immediately — the closure is allocated but always called. This is the non-incremental path with minimal overhead (one small closure per node).

When reuse succeeds, the closure is allocated but **never called** — the grammar body is skipped entirely, giving O(edit) performance.

### Three Grammar Patterns

**1. `node(kind, body)` — leaf and simple nodes (reuse-aware)**

```moonbit
fn parse_atom(ctx) {
  match ctx.peek() {
    Integer(_) => ctx.node(IntLiteral, fn() {
      ctx.emit_token(IntToken)
    })
    Lambda => ctx.node(LambdaExpr, fn() {
      ctx.emit_token(LambdaToken)
      ctx.emit_token(IdentToken)
      lambda_expect(ctx, Dot, DotToken)
      parse_expression(ctx)
    })
  }
}
```

**2. `wrap_at(mark, kind, body)` — retroactive wrapping (no reuse)**

```moonbit
fn parse_binary_op(ctx) {
  let mark = ctx.mark()
  parse_application(ctx)
  match ctx.peek() {
    Plus | Minus => ctx.wrap_at(mark, BinaryExpr, fn() {
      while ctx.error_count < MAX_ERRORS {
        match ctx.peek() {
          Plus => { ctx.emit_token(PlusToken); parse_application(ctx) }
          Minus => { ctx.emit_token(MinusToken); parse_application(ctx) }
          _ => break
        }
      }
    })
    _ => ()
  }
}
```

Cannot reuse because the prefix (first child) is already parsed and emitted. Inner `parse_application` calls still benefit from `node()` reuse on their children.

**3. Raw `start_node`/`finish_node` — opt-out**

```moonbit
// Error recovery — never reuse error nodes
ctx.start_node(ErrorNode)
ctx.bump_error()
ctx.finish_node()
```

### Future Extension: `reusable(body)` (Option A)

For compound expressions built via retroactive wrapping, reuse at `node()` level misses the outer wrapper. A kind-agnostic `reusable()` combinator could check "any reusable node at current offset?" before descending:

```moonbit
fn parse_expression(ctx) {
  ctx.reusable(fn() { parse_binary_op(ctx) })
}
```

This requires the cursor to support `seek_any_node_at(offset)` alongside `seek_node_at(offset, kind)`. Deferred — `node()` reuse covers leaf/simple nodes, which are the majority. `reusable()` is purely additive when needed.

---

## `LanguageSpec` Extensions

Three callbacks added for old-tree interpretation during reuse:

```moonbit
pub struct LanguageSpec[T, K] {
  // --- existing ---
  kind_to_raw : (K) -> @green_tree.RawKind
  token_is_eof : (T) -> Bool
  token_is_trivia : (T) -> Bool
  print_token : (T) -> String
  whitespace_kind : K
  error_kind : K
  root_kind : K
  eof_token : T

  // --- new: reuse support ---
  raw_is_trivia : (@green_tree.RawKind) -> Bool
  raw_is_error : (@green_tree.RawKind) -> Bool
  green_token_matches : (@green_tree.RawKind, String, T) -> Bool
}
```

**Why separate `raw_is_trivia` from `token_is_trivia`?** The old tree contains `RawKind` values, not `T` values. `token_is_trivia` classifies new tokens; `raw_is_trivia` classifies old green leaves. They operate in different type spaces.

**`green_token_matches(raw, text, tok)`** — the core reuse primitive. "Does the old green leaf (RawKind + source text) correspond to this new token T?" This handles payload tokens (identifiers, integers) where kind alone is insufficient — the text/value must also match.

**`tokens_equal` removed** — replaced by `T : Eq` trait bound on methods that need equality. `Token` already derives `Eq`.

### Lambda Implementation

```moonbit
let lambda_spec = LanguageSpec::new(
  // ... existing fields ...
  raw_is_trivia=fn(raw) { raw == @syntax.WhitespaceToken.to_raw() },
  raw_is_error=fn(raw) { raw == @syntax.ErrorToken.to_raw() },
  green_token_matches=fn(raw, text, tok) {
    match @syntax.SyntaxKind::from_raw(raw) {
      IdentToken => match tok { Identifier(name) => name == text; _ => false }
      IntToken => match tok {
        Integer(v) => v.to_string() == text
        _ => false
      }
      _ => match syntax_kind_to_token_kind(raw) {
        Some(expected) => tok == expected
        None => false
      }
    }
  },
)
```

---

## `ReuseCursor[T, K]` in `core`

### Struct

```moonbit
pub struct ReuseCursor[T, K] {
  stack : Array[CursorFrame]
  mut current_offset : Int
  damage_start : Int
  damage_end : Int
  old_tokens : Array[OldToken]         // flattened from old tree
  reuse_globally_disabled : Bool

  // new token stream (indexed accessors, same as ParserContext)
  token_count : Int
  get_token : (Int) -> T
  get_start : (Int) -> Int

  spec : LanguageSpec[T, K]
}
```

Uses `(damage_start, damage_end)` instead of `@range.Range` to avoid a dependency on the `range` package from `core`.

### Genericized Helpers

All helpers that currently reference `@syntax` or `@token` are replaced with `LanguageSpec` callbacks:

| Current (lambda-specific) | Generic (via spec) |
|---|---|
| `t.kind != @syntax.WhitespaceToken.to_raw()` | `not((spec.raw_is_trivia)(t.kind))` |
| `t.kind != @syntax.ErrorToken.to_raw()` | `not((spec.raw_is_error)(t.kind))` |
| `token_matches_syntax_kind(token, text, kind)` | `(spec.green_token_matches)(kind, text, token)` |
| `match info.token { Whitespace => ...; EOF => ... }` | `(spec.token_is_trivia)(tok)` / `(spec.token_is_eof)(tok)` |

### Reuse Check Flow

```
try_reuse(kind: K, byte_offset: Int, token_pos: Int) -> GreenNode?
  1. reuse_globally_disabled?        → None
  2. byte_offset inside damage?      → None
  3. seek_node_at(offset, raw_kind)  → None if no match
  4. is_outside_damage(node)?        → None if overlaps
  5. leading_token_matches(node)?    → None if mismatch
  6. trailing_context_matches(node)? → None if mismatch
  7. Some(node)
```

All six checks use `LanguageSpec` callbacks — no `@syntax`/`@token` references.

---

## `ParserContext` Integration

### New Fields

```moonbit
pub struct ParserContext[T, K] {
  // ... existing fields ...
  mut reuse_cursor : ReuseCursor[T, K]?
  mut reuse_count : Int
}
```

### Byte Offset Derivation

`try_reuse` needs the byte offset of the current non-trivia token. This is derived from existing token accessors — no separate tracking:

```moonbit
fn[T : Eq, K] ParserContext::current_byte_offset(self) -> Int {
  let pos = self.next_non_trivia_pos()
  if pos < self.token_count {
    (self.get_start)(pos)
  } else {
    self.source.length()
  }
}
```

### `emit_reused`

Walks the reused `GreenNode` recursively and pushes `StartNode`/`Token`/`FinishNode` events into the event buffer, then advances `position` past all tokens covered by the node:

```moonbit
fn[T, K] ParserContext::emit_reused(
  self : ParserContext[T, K],
  node : @green_tree.GreenNode,
) -> Unit {
  self.events.push(StartNode(node.kind))
  for child in node.children {
    match child {
      Token(t) => self.events.push(ParseEvent::Token(t.kind, t.text))
      Node(n) => self.emit_reused(n)
    }
  }
  self.events.push(FinishNode)
  // advance position past all tokens in the reused node
  self.advance_past_reused(node)
  self.reuse_count = self.reuse_count + 1
}
```

### `advance_past_reused`

Counts the tokens (including trivia) covered by the reused node's text span, advances `self.position` by that count:

```moonbit
fn[T, K] ParserContext::advance_past_reused(
  self : ParserContext[T, K],
  node : @green_tree.GreenNode,
) -> Unit {
  let node_end = self.current_byte_offset() + node.text_len
  while self.position < self.token_count &&
        (self.get_start)(self.position) < node_end {
    self.position = self.position + 1
  }
}
```

---

## Migration Plan

### Phase 1: Extend `LanguageSpec` and `ParserContext`

1. Add `raw_is_trivia`, `raw_is_error`, `green_token_matches` to `LanguageSpec`
2. Replace `tokens_equal` with `T : Eq` bound
3. Add `reuse_cursor` and `reuse_count` fields to `ParserContext`
4. Implement `node()`, `wrap_at()`, `try_reuse()`, `emit_reused()`
5. Update `lambda_spec` with reuse callbacks

### Phase 2: Move `ReuseCursor` to `core`

1. Copy `ReuseCursor` to `core`, replacing all `@syntax`/`@token` references with `LanguageSpec` callbacks
2. Remove `@range.Range` dependency — use `(damage_start, damage_end)`
3. Add tests using the existing `TestTok`/`TestKind` test language in `lib_wbtest.mbt`
4. Remove old `ReuseCursor` from `parser/`

### Phase 3: Migrate Lambda Grammar to `node()` / `wrap_at()`

1. Convert `parse_atom` to use `ctx.node()`
2. Convert `parse_binary_op` to use `ctx.wrap_at()`
3. Convert `parse_application` to use `ctx.wrap_at()`
4. Wire `parse_green_with_cursor` and `parse_green_recover_with_tokens` to pass cursor into `ParserContext`
5. Verify all 367+ tests pass
6. Benchmark incremental vs full reparse

### Phase 4 (future): `reusable()` for compound expressions

1. Add `seek_any_node_at(offset)` to `ReuseCursor`
2. Implement `reusable(body)` combinator
3. Add at expression entry points for maximum reuse coverage

---

## Key Design Decisions

- **`node()` combinator over transparent `start_node`**: Closure enables skipping the grammar body entirely on reuse hit — true O(edit). Transparent `start_node` can only suppress events while still running grammar code — O(N) with constant reduction.
- **Dictionary passing over traits**: MoonBit's orphan rule prevents `impl @core.Trait for @token.Type` in the `parser` package. `LanguageSpec` closures avoid dependency pollution.
- **`Eq` bound instead of `tokens_equal` closure**: Builtin trait, already derived. One fewer closure, compile-time checked.
- **Byte offset derived, not tracked**: `(get_start)(next_non_trivia_pos())` gives the byte offset on demand. No additional mutable state.
- **Damage range as `(Int, Int)`, not `@range.Range`**: Avoids adding `range` package as dependency to `core`.
- **Start with exact-kind reuse (B), add kind-agnostic (A) later**: `node(kind, body)` covers leaf/simple nodes. `reusable(body)` is additive when needed for compound expressions.
