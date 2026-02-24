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

`LanguageSpec` is dictionary passing made explicit: a record of closures that carries language-specific behavior through the framework. If profiling ever shows closure indirection matters in a hot loop, specific callbacks can be defunctionalized into tagged enums. For now, dictionary passing is the correct abstraction level.

---

## Grammar API: The `node()` Combinator

### The Problem

In an imperative parser, `start_node(kind)` is called inside the grammar function body. To skip the body on reuse, the framework must not execute it. But `start_node` cannot unwind its caller.

### The Solution

Wrap the body in a closure. The framework decides whether to call it:

```moonbit
pub fn[T, K] ParserContext::node(
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

When reuse succeeds, the closure is **never called** — the grammar body is skipped entirely, giving O(edit) performance.

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
          Plus  => { ctx.emit_token(PlusToken);  parse_application(ctx) }
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

`wrap_at` is a thin wrapper — it does not exist yet in `core` and must be added:

```moonbit
pub fn[T, K] ParserContext::wrap_at(
  self : ParserContext[T, K],
  mark : Int,
  kind : K,
  body : () -> Unit,
) -> Unit {
  self.start_at(mark, kind)
  body()
  self.finish_node()
}
```

**3. Raw `start_node`/`finish_node` — opt-out**

```moonbit
// Error recovery — never reuse error nodes
ctx.start_node(ErrorNode)
ctx.bump_error()
ctx.finish_node()
```

### Future Extension: `reusable(body)`

For compound expressions built via retroactive wrapping, reuse at `node()` level misses the outer wrapper. A kind-agnostic `reusable()` combinator could check "any reusable node at current offset?" before descending:

```moonbit
fn parse_expression(ctx) {
  ctx.reusable(fn() { parse_binary_op(ctx) })
}
```

Deferred — `node()` reuse covers leaf/simple nodes, which are the majority. `reusable()` is purely additive when needed.

---

## `LanguageSpec` Extensions

Three callbacks added for old-tree interpretation during reuse:

```moonbit
pub struct LanguageSpec[T, K] {
  // --- existing ---
  kind_to_raw : (K) -> @green_tree.RawKind
  token_is_eof : (T) -> Bool
  token_is_trivia : (T) -> Bool
  tokens_equal : (T, T) -> Bool
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

### Lambda Implementation

```moonbit
let lambda_spec = LanguageSpec::new(
  // ... existing fields unchanged ...
  raw_is_trivia=fn(raw) { raw == @syntax.WhitespaceToken.to_raw() },
  raw_is_error=fn(raw) { raw == @syntax.ErrorToken.to_raw() },
  green_token_matches=fn(raw, text, tok) {
    match @syntax.SyntaxKind::from_raw(raw) {
      IdentToken => match tok { Identifier(name) => name == text; _ => false }
      IntToken   => match tok { Integer(v) => v.to_string() == text; _ => false }
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

### `try_reuse`

Uses `(self.get_start)(self.position)` — the absolute byte offset of the current token — as the seek anchor. This is the node's actual start including any leading trivia, which is what `seek_node_at` matches on:

```moonbit
fn[T, K] ParserContext::try_reuse(
  self : ParserContext[T, K],
  kind : K,
) -> @green_tree.GreenNode? {
  if self.position >= self.token_count { return None }
  let byte_offset = (self.get_start)(self.position)
  match self.reuse_cursor {
    None => None
    Some(cursor) => cursor.try_reuse(
      (self.spec.kind_to_raw)(kind),
      byte_offset,
      self.position,
    )
  }
}
```

**Why `get_start(position)` not a non-trivia byte offset?** `seek_node_at` matches by a node's absolute start offset, which includes any leading trivia stored as first children (because `flush_trivia` runs inside `emit_token`, after `start_node`). Using the non-trivia offset would seek to the wrong position and miss valid nodes.

### `emit_reused`

Event emission and position advancement are **separate concerns** and must not be mixed. Combining them in a single recursive function causes `position` to advance multiple times for a single node (once per child, once per intermediate node).

```moonbit
fn[T, K] ParserContext::emit_reused(
  self : ParserContext[T, K],
  node : @green_tree.GreenNode,
) -> Unit {
  self.emit_node_events(node)       // recursive: only emits events
  self.advance_past_reused(node)    // once: advances ParserContext.position
  match self.reuse_cursor {
    Some(cursor) => cursor.advance_past(node)  // keeps cursor.current_offset in sync
    None => ()
  }
  self.reuse_count = self.reuse_count + 1
}

fn[T, K] ParserContext::emit_node_events(
  self : ParserContext[T, K],
  node : @green_tree.GreenNode,
) -> Unit {
  self.events.push(@green_tree.StartNode(node.kind))
  for child in node.children {
    match child {
      @green_tree.Token(t) => self.events.push(@green_tree.ParseEvent::Token(t.kind, t.text))
      @green_tree.Node(n)  => self.emit_node_events(n)
    }
  }
  self.events.push(@green_tree.FinishNode)
}
```

### `advance_past_reused`

`GreenNode.token_count` already stores the non-trivia leaf count, specifically for this purpose (see `green_node.mbt` comment). Advance `position` by counting down `token_count` non-trivia tokens, skipping trivia as encountered:

```moonbit
fn[T, K] ParserContext::advance_past_reused(
  self : ParserContext[T, K],
  node : @green_tree.GreenNode,
) -> Unit {
  let mut remaining = node.token_count
  while remaining > 0 && self.position < self.token_count {
    let tok = (self.get_token)(self.position)
    self.position = self.position + 1
    if not (self.spec.token_is_trivia)(tok) {
      remaining = remaining - 1
    }
  }
}
```

**Why `token_count` not byte arithmetic?** Leading trivia is stored inside nodes (emitted by `flush_trivia` inside `emit_token`, which runs after `start_node`). So `node.token_count` non-trivia tokens plus any interleaved trivia exactly covers the node's full token span. No byte offset computation needed.

**Why not `position += node.token_count`?** `ParserContext.position` is a raw index including trivia. `token_count` is non-trivia only. The forward scan naturally handles both.

---

## Migration Plan

### Phase 1: Extend `LanguageSpec` and `ParserContext`

1. Add `raw_is_trivia`, `raw_is_error`, `green_token_matches` to `LanguageSpec` and `LanguageSpec::new`
2. Add `reuse_cursor` and `reuse_count` fields to `ParserContext`
3. Implement `node()`, `wrap_at()`, `try_reuse()`, `emit_reused()`, `emit_node_events()`, `advance_past_reused()`
4. Update `lambda_spec` with new reuse callbacks

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
- **Damage range as `(Int, Int)`, not `@range.Range`**: Avoids adding `range` package as dependency to `core`.
- **Seek by absolute position, not non-trivia byte offset**: `seek_node_at` matches nodes by their absolute start offset. Leading trivia belongs inside nodes (placed there by `flush_trivia` inside `emit_token`). Using `get_start(position)` gives the correct anchor; a non-trivia offset would miss valid nodes.
- **`token_count` forward scan, not byte arithmetic**: `GreenNode.token_count` exists precisely for advancing position after reuse. The forward scan handles mixed trivia/non-trivia correctly without byte offset computation.
- **`emit_node_events` and `advance_past_reused` are separate**: Combining them recursively would advance `position` once per child node, corrupting the token stream position. Event emission is pure and recursive; position advancement happens once at the top level.
- **`cursor.advance_past(node)` after reuse**: Keeps `ReuseCursor.current_offset` in sync so subsequent seeks correctly detect backward movement and reset if needed.
- **Start with exact-kind reuse, add kind-agnostic later**: `node(kind, body)` covers leaf/simple nodes. `reusable(body)` is additive when needed for compound expressions.
