# Design: Extract `green-tree` Package from `syntax`

> Historical design artifact (2026-02-19). This document reflects pre-implementation
> architecture intent and may not match current code exactly.
>
> For current behavior, use the active documentation set in `docs/` and this
> directory's documentation index. Do not treat this design note as the source of truth.

**Date:** 2026-02-19
**Status:** Approved

## Goal

Refactor `src/syntax/` to separate language-independent green-red tree infrastructure
from lambda-calculus-specific syntax kinds. The result is a reusable `green-tree`
package (rowan-style) that other parsers and the incr integration can depend on.

## Why

`src/syntax/` currently mixes two concerns:

1. **Generic tree infrastructure** — `GreenNode`, `GreenToken`, `GreenElement`,
   `RedNode`, `EventBuffer`, `build_tree` — these are language-independent.
2. **Language-specific definitions** — `SyntaxKind` enum with lambda calculus
   tokens (`LambdaToken`, `IfKeyword`, etc.).

Separating them enables:
- Reuse of green-red tree in other parsers/projects
- Integration with incr (incremental computation library) where `GreenNode` serves
  as a `Memo[GreenNode]` value — **hash-based O(1) `Eq` is critical** for incr's
  backdating optimization
- Clean separation of concerns following rust-analyzer's rowan architecture

## Package Structure

```
src/
  green-tree/           # NEW — zero dependencies
    green_node.mbt      # RawKind, GreenToken, GreenElement, GreenNode (with hash)
    red_node.mbt        # RedNode
    event.mbt           # ParseEvent, EventBuffer, build_tree (parameterized root_kind)
    hash.mbt            # combine_hash, string_hash
    moon.pkg.json       # {} — no imports

  syntax/               # MODIFIED — depends on green-tree
    syntax_kind.mbt     # SyntaxKind enum + to_raw() / from_raw()
    moon.pkg.json       # { "import": ["dowdiness/parser/green-tree"] }
    # green_tree.mbt, red_tree.mbt, parse_events.mbt → REMOVED

  parser/               # imports both @green_tree and @syntax
  incremental/          # imports both @green_tree and @syntax
```

**Re-export strategy:** All downstream packages import `@green_tree` directly.
`syntax/` does not re-export green-tree types.

## Data Model

### `green-tree/green_node.mbt`

```moonbit
/// Language-independent node kind (rowan's RawSyntaxKind equivalent)
pub(all) type RawKind Int derive(Eq, Show, Hash)

pub(all) struct GreenToken {
  kind : RawKind
  text : String
  hash : Int
} derive(Show)

pub(all) enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
} derive(Show)

pub(all) struct GreenNode {
  kind : RawKind
  children : Array[GreenElement]
  text_len : Int
  hash : Int
} derive(Show)
```

**Constructor functions** auto-compute hash:
- `GreenToken::new(kind, text)` — `hash = combine(kind_hash, string_hash(text))`
- `GreenNode::new(kind, children)` — `hash = fold over children hashes`, `text_len = sum`

**`Eq` implementations** — hash fast-path, structural comparison only on collision:
- `GreenToken Eq`: hash first, then `kind + text`
- `GreenNode Eq`: hash first, then `kind + children.length() + recursive children`
- `GreenElement Eq`: delegate to Token/Node

**Accessor functions:**
- `GreenToken::text_len(self) -> Int` — returns `self.text.length()` (no field)
- `GreenElement::text_len(self) -> Int`
- `GreenElement::kind(self) -> RawKind`
- `GreenNode::kind(self) -> RawKind`
- `GreenNode::has_errors(self, error_node_kind: RawKind, error_token_kind: RawKind) -> Bool`
  — replaces the free function `has_green_errors`

**Not included (deferred):**
- `GreenNode::width()` alias — no call sites yet
- `RedNode::node_at(position)` — no call sites yet; needed for incr but deferred

### `green-tree/hash.mbt`

```moonbit
pub fn combine_hash(h: Int, value: Int) -> Int {
  h.lxor(value) * 16777619  // FNV prime
}

pub fn string_hash(s: String) -> Int {
  let mut h = 2166136261  // FNV offset basis
  for i = 0; i < s.length(); i = i + 1 {
    h = combine_hash(h, s.code_unit_at(i).to_int())
  }
  h
}
```

### `green-tree/red_node.mbt`

`RedNode` moves from `syntax/red_tree.mbt` unchanged except:
- `RedNode::kind()` returns `RawKind` (was `SyntaxKind`)

```moonbit
pub struct RedNode {
  green : GreenNode
  parent : RedNode?
  offset : Int
}
```

Methods to preserve: `new`, `from_green`, `start`, `end`, `kind`, `children`

### `green-tree/event.mbt`

`ParseEvent`, `EventBuffer`, `build_tree` move from `syntax/parse_events.mbt`.

**Critical change:** `ParseEvent::StartNode` takes `RawKind` instead of `SyntaxKind`.
`build_tree` accepts `root_kind: RawKind` parameter instead of hardcoding `SourceFile`.

```moonbit
pub(all) enum ParseEvent {
  StartNode(RawKind)
  FinishNode
  Token(RawKind, String)
  Tombstone
} derive(Show, Eq)

pub fn build_tree(events: Array[ParseEvent], root_kind: RawKind) -> GreenNode
```

`EventBuffer.events` field stays `pub` — `green_parser.mbt` accesses it directly.

## Conversion Layer: `syntax/syntax_kind.mbt`

Keep the existing `SyntaxKind` enum and `is_token` method. Add:

```moonbit
pub fn SyntaxKind::to_raw(self: SyntaxKind) -> @green_tree.RawKind {
  let n: Int = match self {
    LambdaToken      => 0
    DotToken         => 1
    LeftParenToken   => 2
    RightParenToken  => 3
    PlusToken        => 4
    MinusToken       => 5
    IfKeyword        => 6
    ThenKeyword      => 7
    ElseKeyword      => 8
    IdentToken       => 9
    IntToken         => 10
    WhitespaceToken  => 11
    ErrorToken       => 12
    EofToken         => 13
    LambdaExpr       => 14
    AppExpr          => 15
    BinaryExpr       => 16
    IfExpr           => 17
    ParenExpr        => 18
    IntLiteral       => 19
    VarRef           => 20
    ErrorNode        => 21
    SourceFile       => 22
  }
  @green_tree.RawKind(n)
}

pub fn SyntaxKind::from_raw(raw: @green_tree.RawKind) -> SyntaxKind {
  match raw._ {
    0  => LambdaToken
    1  => DotToken
    2  => LeftParenToken
    3  => RightParenToken
    4  => PlusToken
    5  => MinusToken
    6  => IfKeyword
    7  => ThenKeyword
    8  => ElseKeyword
    9  => IdentToken
    10 => IntToken
    11 => WhitespaceToken
    12 => ErrorToken
    13 => EofToken
    14 => LambdaExpr
    15 => AppExpr
    16 => BinaryExpr
    17 => IfExpr
    18 => ParenExpr
    19 => IntLiteral
    20 => VarRef
    21 => ErrorNode
    22 => SourceFile
    _  => ErrorNode
  }
}
```

## Downstream Call Site Changes

### `parser/green_parser.mbt`

Add local helper at top of file:
```moonbit
fn raw(kind: @syntax.SyntaxKind) -> @green_tree.RawKind { kind.to_raw() }
```

Then:
- `@syntax.StartNode(kind)` → `@green_tree.StartNode(raw(kind))`
- `@syntax.ParseEvent::Token(kind, text)` → `@green_tree.ParseEvent::Token(raw(kind), text)`
- `@syntax.FinishNode` → `@green_tree.FinishNode`
- `@syntax.build_tree(parser.events.events)` → `@green_tree.build_tree(parser.events.events, raw(SourceFile))` (3 call sites)
- `@syntax.EventBuffer::new()` → `@green_tree.EventBuffer::new()`
- Type annotations `@syntax.GreenNode` / `@syntax.GreenElement` → `@green_tree.*`

### `parser/reuse_cursor.mbt`

The largest change. All `@syntax.GreenNode`, `@syntax.GreenElement`, `@syntax.GreenToken`
type references update to `@green_tree.*`.

For `SyntaxKind` comparisons (e.g., `t.kind != @syntax.WhitespaceToken`):
- `t.kind` is now `RawKind`, so comparisons become `t.kind != @syntax.WhitespaceToken.to_raw()`
- Or declare module-level constants: `let whitespace_raw = @syntax.WhitespaceToken.to_raw()`

Public API changes:
- `try_reuse(expected_kind: @syntax.SyntaxKind, ...)` → `try_reuse(expected_kind: @green_tree.RawKind, ...)`
- `seek_node_at(target_offset, expected_kind: @syntax.SyntaxKind)` → `RawKind`

Internal functions `first_token_kind`, `last_token_kind` return `@green_tree.RawKind?` instead of
`@syntax.SyntaxKind?`. `syntax_kind_to_token_kind` and `token_matches_syntax_kind` are updated
to work with `RawKind` by converting via `from_raw()` when needed for token comparisons.

Call sites in `green_parser.mbt`:
- `try_reuse(@syntax.IntLiteral)` → `try_reuse(raw(IntLiteral))`

### `parser/green_convert.mbt`

`convert_red` matches on `g.kind` (now `RawKind`):
```moonbit
// Before:
match g.kind {
  @syntax.IntLiteral => ...

// After:
match @syntax.SyntaxKind::from_raw(g.kind) {
  IntLiteral => ...
```

### `incremental/incremental_parser.mbt`

- `green_tree: @syntax.GreenNode?` field → `@green_tree.GreenNode?`
- Add `@green_tree` to `moon.pkg.json` imports

### `incremental/perf_instrumentation.mbt`

Update any `@syntax.GreenNode` type references to `@green_tree.GreenNode`.

### Test files (`green_tree_test.mbt`, `reuse_cursor_test.mbt`)

Update imports and type references to use `@green_tree.*` directly.

## Constraints

1. All existing tests must pass (imports may need updating, behavior unchanged)
2. Do not change `SyntaxKind` variant names or `is_token` method
3. `GreenNode Eq` must be hash-based (behavioral improvement, same results)
4. `build_tree` must accept `root_kind` parameter — all 3 call sites updated
5. `green-tree/moon.pkg.json` must have zero imports
6. Integer mappings in `to_raw`/`from_raw` are stable (never reorder)

## Migration Order

Execute in this order to keep the build green at each step:

1. **Create `src/green-tree/`** — implement `hash.mbt`, `green_node.mbt`, `red_node.mbt`, `event.mbt` with `moon.pkg.json` (zero imports)
2. **Update `src/syntax/`** — remove moved files, add `syntax_kind.mbt` with `to_raw`/`from_raw`, update `moon.pkg.json`
3. **Update `src/parser/`** — add `green-tree` to imports, migrate `green_parser.mbt`, `reuse_cursor.mbt`, `green_convert.mbt`, test files
4. **Update `src/incremental/`** — add `green-tree` to imports, update type references
5. **Run `moon check && moon test`** — fix any remaining type errors

## Verification

After implementation:

1. `moon check` passes with no errors
2. `moon test` — all existing tests pass
3. `green-tree/moon.pkg.json` has no imports
4. `syntax/moon.pkg.json` imports only `green-tree`
5. Hash-based equality works:
   ```moonbit
   test "green node hash equality" {
     let a = @green_tree.GreenNode::new(@green_tree.RawKind(0), [])
     let b = @green_tree.GreenNode::new(@green_tree.RawKind(0), [])
     assert_true(a == b)
   }
   ```
