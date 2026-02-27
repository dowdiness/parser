# Task: Extract language-independent `green-tree` package from parser's `syntax` package

## Goal

Refactor the `src/syntax/` package to separate the **language-independent green-red tree data structure** from the **lambda-calculus-specific syntax kinds**. This creates a reusable `green-tree` package (rowan-style) that can be shared across projects, including integration with an external incremental computation library (incr).

## Why

Currently `src/syntax/` mixes two concerns:
1. **Generic tree infrastructure**: `GreenNode`, `GreenToken`, `GreenElement`, `RedNode`, `EventBuffer`, `build_tree` — these are language-independent
2. **Language-specific definitions**: `SyntaxKind` enum with lambda calculus tokens (`LambdaToken`, `IfKeyword`, etc.) — these are specific to this parser

The extraction enables:
- Reuse of the green-red tree in other parsers/projects
- Integration with incr (incremental computation library) where `GreenNode` serves as a `Memo[GreenNode]` value — **hash-based O(1) `Eq` is critical for incr's backdating optimization** (if recomputation yields the same GreenNode hash, all downstream Memos skip recomputation)
- Clean separation of concerns following rust-analyzer's architecture (rowan = generic green-red tree, separate from language-specific syntax definitions)
- Hashing strategy split by concern:
  - cached structural hash (construction-time) for fast `Eq`
  - `Hash` trait impls for `HashMap`/`HashSet` interoperability

## Current File Structure

```
src/
  syntax/
    green_tree.mbt      # SyntaxKind enum + GreenToken + GreenElement + GreenNode + has_green_errors
    red_tree.mbt         # RedNode
    parse_events.mbt     # ParseEvent + EventBuffer + build_tree (hardcodes SourceFile)
    moon.pkg.json        # {} (no dependencies)
    pkg.generated.mbti   # Generated interface
  parser/               # Depends on syntax
  lexer/                # Independent
  incremental/          # Depends on parser, syntax
  token/                # Independent
  term/                 # Independent
  range/                # Independent
  edit/                 # Independent
```

## Target File Structure

```
src/
  green-tree/           # NEW: language-independent package
    green_node.mbt      # RawKind + GreenToken + GreenElement + GreenNode (with hash)
    red_node.mbt         # RedNode (with node_at)
    event.mbt            # ParseEvent + EventBuffer + build_tree (parameterized root_kind)
    hash.mbt             # FNV utility functions for cached structural hash
    moon.pkg.json        # {} (no dependencies)
  syntax/               # MODIFIED: language-specific, depends on green-tree
    syntax_kind.mbt      # SyntaxKind enum + to_raw() / from_raw() conversion
    moon.pkg.json        # { "import": ["dowdiness/parser/green-tree"] }
  parser/               # Depends on syntax AND green-tree
  incremental/          # Depends on parser, syntax, green-tree
  ...
```

## Detailed Specifications

### 1. `green-tree/green_node.mbt`

Key design decisions:
- **`RawKind` = newtype over `Int`** (following rowan's `RawSyntaxKind`). Languages provide their own enum and convert to/from `RawKind`.
- **Hash field on every node/token** for O(1) equality comparison. This is essential for incr integration where `Memo::force_recompute` compares old and new `GreenNode` values — if hashes match, backdating kicks in and all downstream computation is skipped.
- **Hybrid hash model**:
  - constructors compute cached structural hash using `hash.mbt` (FNV)
  - `Hash` trait impls reuse cached hash for MoonBit collections (`hasher.combine_int(self.hash)`)
- **`Eq` implementation**: compare hash first (fast path), then fall back to structural comparison only on hash collision.

```moonbit
/// Language-independent node kind (rowan's RawSyntaxKind equivalent)
/// Each language defines its own enum and converts to/from this.
pub(all) type RawKind Int derive(Eq, Show, Hash)

pub(all) struct GreenToken {
  kind : RawKind
  text : String
  hash : Int
} derive(Show)

pub(all) struct GreenNode {
  kind : RawKind
  children : Array[GreenElement]
  text_len : Int
  hash : Int
} derive(Show)

pub(all) enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
} derive(Show)
```

**Constructor functions** must auto-compute hash:
- `GreenToken::new(kind, text)` — hash = combine(kind, string_hash(text))
- `GreenNode::new(kind, children)` — hash = fold over children hashes, text_len = sum of children text_len

**`Eq` implementations**:
- `GreenToken`: hash equality first, then kind + text on collision
- `GreenNode`: hash equality first, then kind + children length + recursive children comparison on collision
- `GreenElement`: delegate to Token/Node Eq

**Accessor functions** (preserve existing API surface):
- `GreenElement::text_len() -> Int`
- `GreenElement::kind() -> RawKind`
- `GreenNode::width() -> Int` (alias for text_len)
- `GreenNode::has_errors(error_node_kind: RawKind, error_token_kind: RawKind) -> Bool`

### 2. `green-tree/hash.mbt` + `Hash` trait interop

```moonbit
pub fn combine_hash(h : Int, value : Int) -> Int {
  let mixed = h.lxor(value)
  mixed * 16777619  // FNV prime
}

pub fn string_hash(s : String) -> Int {
  let mut h = 2166136261  // FNV offset basis
  for i = 0; i < s.length(); i = i + 1 {
    h = combine_hash(h, s.code_unit_at(i).to_int())
  }
  h
}
```

These FNV utilities are used for constructor-time cached structural hashing.
Collection interop (`HashMap`, `HashSet`) is provided by `Hash` trait impls on
`GreenToken`, `GreenElement`, and `GreenNode` that reuse those cached values.

### 3. `green-tree/red_node.mbt`

Move existing `RedNode` from `syntax/red_tree.mbt`. Change `GreenNode`/`SyntaxKind` references to use the new `green-tree` types. Add `node_at` for position-based lookup:

```moonbit
pub struct RedNode {
  green : GreenNode
  parent : RedNode?
  offset : Int
}
```

Methods to preserve:
- `RedNode::new(green, parent, offset)`
- `RedNode::from_green(green)` — creates root RedNode with offset=0
- `RedNode::start() -> Int`
- `RedNode::end() -> Int`
- `RedNode::kind() -> RawKind`  (was SyntaxKind, now RawKind)
- `RedNode::children() -> Array[RedNode]`

New method:
- `RedNode::node_at(position: Int) -> RedNode` — find deepest node containing position

### 4. `green-tree/event.mbt`

Move `ParseEvent`, `EventBuffer`, and `build_tree` from `syntax/parse_events.mbt`.

**Critical change**: `build_tree` must accept `root_kind: RawKind` as parameter instead of hardcoding `SourceFile`:

```moonbit
pub(all) enum ParseEvent {
  StartNode(RawKind)
  FinishNode
  Token(RawKind, String)
  Tombstone
} derive(Show, Eq)

pub fn build_tree(events : Array[ParseEvent], root_kind : RawKind) -> GreenNode
```

`EventBuffer` methods:
- `EventBuffer::new()`
- `EventBuffer::push(event)`
- `EventBuffer::mark() -> Int`
- `EventBuffer::start_at(mark, kind: RawKind)`

### 5. `syntax/syntax_kind.mbt`

Keep the existing `SyntaxKind` enum **in syntax/**. Add conversion functions:

```moonbit
pub fn SyntaxKind::to_raw(self : SyntaxKind) -> @green_tree.RawKind {
  // Assign stable integer values to each variant
  let n : Int = match self {
    LambdaToken => 0
    DotToken => 1
    LeftParenToken => 2
    RightParenToken => 3
    PlusToken => 4
    MinusToken => 5
    IfKeyword => 6
    ThenKeyword => 7
    ElseKeyword => 8
    IdentToken => 9
    IntToken => 10
    WhitespaceToken => 11
    ErrorToken => 12
    EofToken => 13
    LambdaExpr => 14
    AppExpr => 15
    BinaryExpr => 16
    IfExpr => 17
    ParenExpr => 18
    IntLiteral => 19
    VarRef => 20
    ErrorNode => 21
    SourceFile => 22
  }
  @green_tree.RawKind(n)
}

pub fn SyntaxKind::from_raw(raw : @green_tree.RawKind) -> SyntaxKind {
  match raw._ {
    0 => LambdaToken
    1 => DotToken
    2 => LeftParenToken
    3 => RightParenToken
    4 => PlusToken
    5 => MinusToken
    6 => IfKeyword
    7 => ThenKeyword
    8 => ElseKeyword
    9 => IdentToken
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
    _ => ErrorNode  // fallback for unknown kinds
  }
}
```

Also add a convenience constant or function for the `SourceFile` root kind used by `build_tree`:
```moonbit
pub fn source_file_raw() -> @green_tree.RawKind {
  SourceFile.to_raw()
}
```

Re-export or provide bridge functions so existing code that uses `@syntax.GreenNode`, `@syntax.GreenToken`, etc. continues to work. The simplest approach: `syntax/` re-exports the types from `green-tree` via type aliases or wrapper functions. Alternatively, update all downstream imports to use `@green_tree` directly.

### 6. Downstream changes

#### `syntax/moon.pkg.json`
```json
{
  "import": [
    "dowdiness/parser/green-tree"
  ]
}
```

The `syntax` package should re-export green-tree types OR all downstream consumers should import `green-tree` directly. Choose the approach that minimizes code changes. The recommended approach is:
- `syntax/` keeps `SyntaxKind` and conversion functions
- `syntax/` may provide convenience functions that wrap green-tree functions with `SyntaxKind` (e.g., `build_tree_source_file(events)` that calls `@green_tree.build_tree(events, SourceFile.to_raw())`)
- Downstream packages (`parser/`, `incremental/`) import BOTH `syntax` and `green-tree`

#### `parser/moon.pkg.json`
Add `"dowdiness/parser/green-tree"` to imports.

#### `parser/green_parser.mbt`
- `GreenParser` internally uses `RawKind` for events
- Helper functions convert `SyntaxKind` to `RawKind` when emitting events
- `build_tree` call passes `SyntaxKind::SourceFile.to_raw()` as root_kind

The simplest migration path for the parser: create a local helper:
```moonbit
fn raw(kind : @syntax.SyntaxKind) -> @green_tree.RawKind {
  kind.to_raw()
}
```
Then replace `@syntax.StartNode(kind)` with `@green_tree.StartNode(raw(kind))`, etc.

#### `parser/green_convert.mbt`
- `convert_red` receives `@green_tree.RedNode` and uses `from_raw()` to match on `SyntaxKind`
- Pattern: `match @syntax.SyntaxKind::from_raw(red.kind()) { ... }`

#### `parser/reuse_cursor.mbt`
- Update type references from `@syntax.GreenNode` to `@green_tree.GreenNode`
- `SyntaxKind` comparisons use `to_raw()` or the cursor operates on `RawKind` directly

#### `incremental/`
- Update imports and type references similarly

## Constraints

1. **All existing tests must pass unchanged.** The refactoring is purely structural — no behavioral changes.
2. **Do not change the `SyntaxKind` enum values or variant names.** Only add `to_raw`/`from_raw`.
3. **`GreenNode` equality must be hash-based.** The current `derive(Eq)` does deep structural comparison. The new implementation must check hash first for O(1) fast path. This is a behavioral improvement but should be compatible (same results, faster).
4. **`build_tree` must accept `root_kind` parameter.** All call sites must be updated.
5. **The `green-tree` package must have zero dependencies.** It must not import any other package in this project.
6. **Maintain backward compatibility** where possible. If `@syntax.GreenNode` was used by consumers, either re-export from syntax or update all import sites.

## Verification Steps

After implementation, verify:

1. `moon check` passes with no errors
2. `moon test` — all existing tests pass (parser, lexer, incremental, syntax)
3. `green-tree/moon.pkg.json` has no imports (zero dependencies)
4. `syntax/moon.pkg.json` imports only `green-tree`
5. Hash-based equality works:
   ```moonbit
   test "green node hash equality" {
     let a = @green_tree.GreenNode::new(RawKind(0), [])
     let b = @green_tree.GreenNode::new(RawKind(0), [])
     assert_true(a == b)  // hash-based fast path
   }
   ```
6. Structural sharing is preserved:
   ```moonbit
   test "identical subtrees are equal" {
     let leaf1 = @green_tree.GreenElement::Token(
       @green_tree.GreenToken::new(RawKind(9), "x")
     )
     let leaf2 = @green_tree.GreenElement::Token(
       @green_tree.GreenToken::new(RawKind(9), "x")
     )
     assert_true(leaf1 == leaf2)
   }
   ```

## Migration Order

Execute in this order to maintain a working build at each step:

1. **Create `src/green-tree/` package** with `moon.pkg.json` (empty imports), implement `green_node.mbt`, `hash.mbt`, `red_node.mbt`, `event.mbt`
2. **Update `src/syntax/`**: remove moved code, add `syntax_kind.mbt` with `to_raw`/`from_raw`, update `moon.pkg.json` to import `green-tree`, add bridge/re-export as needed
3. **Update `src/parser/`**: update imports and all `SyntaxKind` → `RawKind` conversion points
4. **Update `src/incremental/`**: update imports and type references
5. **Run full test suite**, fix any remaining type errors

## Reference: Current API Surface to Preserve

From `src/syntax/pkg.generated.mbti`, the following public API must remain accessible (either from `green-tree` or `syntax`):

```
// These move to green-tree (with RawKind instead of SyntaxKind):
GreenNode, GreenNode::new, GreenNode::kind
GreenToken, GreenToken::new, GreenToken::text_len
GreenElement, GreenElement::kind, GreenElement::text_len
RedNode, RedNode::new, RedNode::from_green, RedNode::start, RedNode::end, RedNode::kind, RedNode::children
EventBuffer, EventBuffer::new, EventBuffer::push, EventBuffer::mark, EventBuffer::start_at
ParseEvent (StartNode, FinishNode, Token, Tombstone)
build_tree
has_green_errors  (→ GreenNode::has_errors with error kind parameters)

// These stay in syntax:
SyntaxKind (all variants)
SyntaxKind::is_token
```

## Notes

- The `GreenToken::text_len` method currently exists. In the new version, `text_len` can simply be `self.text.length()` — no need for a separate field.
- The current `GreenNode` uses `derive(Eq)` which does deep structural comparison. The new hash-based `Eq` is strictly better (same correctness, O(1) common case).
- `RedNode::kind()` will return `RawKind` instead of `SyntaxKind`. Downstream code that needs `SyntaxKind` calls `SyntaxKind::from_raw(red.kind())`.
- The `has_green_errors` free function becomes `GreenNode::has_errors(self, error_node_kind, error_token_kind)` — the caller passes the language-specific error kinds.
