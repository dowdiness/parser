# Green-Tree Extraction Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract language-independent green-red tree infrastructure from `src/syntax/` into a new zero-dependency `src/green-tree/` package, with hash-based `Eq` for O(1) node comparison.

**Architecture:** Create `src/green-tree/` with `RawKind` (newtype over `Int`), hash-bearing `GreenNode`/`GreenToken`, `RedNode`, `EventBuffer`, and `build_tree`. Update `src/syntax/` to keep only `SyntaxKind` with `to_raw()`/`from_raw()` conversions. All downstream packages (`parser/`, `incremental/`) import `@green_tree` and `@syntax` directly.

**Tech Stack:** MoonBit, `moon check`, `moon test`, `moon test --update` (for snapshot updates)

---

### Task 1: Create `green-tree` package scaffold and `hash.mbt`

**Files:**
- Create: `src/green-tree/moon.pkg.json`
- Create: `src/green-tree/hash.mbt`
- Create: `src/green-tree/hash_test.mbt`

**Step 1: Create the package manifest**

Create `src/green-tree/moon.pkg.json`:
```json
{}
```
This must stay empty forever — `green-tree` has zero project dependencies.

**Step 2: Write the failing hash test**

Create `src/green-tree/hash_test.mbt`:
```moonbit
///|
test "string_hash is deterministic" {
  inspect(string_hash("hello") == string_hash("hello"), content="true")
}

///|
test "string_hash differs for different strings" {
  inspect(string_hash("a") == string_hash("b"), content="false")
}

///|
test "combine_hash is nonzero for nonzero inputs" {
  inspect(combine_hash(1, 2) != 0, content="true")
}
```

**Step 3: Run to verify it fails**

```bash
cd /path/to/parser && moon test src/green-tree
```
Expected: FAIL — `string_hash` and `combine_hash` undefined.

**Step 4: Implement `hash.mbt`**

Create `src/green-tree/hash.mbt`:
```moonbit
///|
/// FNV-1a hash combination. Used to compute structural hashes for GreenNode/GreenToken.
pub fn combine_hash(h : Int, value : Int) -> Int {
  let mixed = h.lxor(value)
  mixed * 16777619 // FNV prime
}

///|
/// FNV-1a string hash. Used to hash GreenToken text.
pub fn string_hash(s : String) -> Int {
  let mut h = 2166136261 // FNV offset basis (as signed Int)
  for i = 0; i < s.length(); i = i + 1 {
    h = combine_hash(h, s.code_unit_at(i).to_int())
  }
  h
}
```

**Step 5: Run tests to verify they pass**

```bash
moon test src/green-tree
```
Expected: All 3 tests PASS.

**Step 6: Commit**

```bash
git add src/green-tree/moon.pkg.json src/green-tree/hash.mbt src/green-tree/hash_test.mbt
git commit -m "feat(green-tree): add package scaffold and FNV hash utilities"
```

---

### Task 2: Implement `green_node.mbt`

**Files:**
- Create: `src/green-tree/green_node.mbt`
- Create: `src/green-tree/green_node_test.mbt`

**Step 1: Write the failing tests**

Create `src/green-tree/green_node_test.mbt`:
```moonbit
///|
test "RawKind equality" {
  let a = RawKind(5)
  let b = RawKind(5)
  let c = RawKind(6)
  inspect(a == b, content="true")
  inspect(a == c, content="false")
}

///|
test "GreenToken constructor computes hash" {
  let t = GreenToken::new(RawKind(9), "hello")
  inspect(t.text, content="hello")
  inspect(t.kind == RawKind(9), content="true")
  // Hash is nonzero
  inspect(t.hash != 0, content="true")
}

///|
test "GreenToken Eq is hash-based fast path" {
  let a = GreenToken::new(RawKind(9), "x")
  let b = GreenToken::new(RawKind(9), "x")
  let c = GreenToken::new(RawKind(9), "y")
  inspect(a == b, content="true")
  inspect(a == c, content="false")
}

///|
test "GreenToken text_len" {
  let t = GreenToken::new(RawKind(9), "hello")
  inspect(t.text_len(), content="5")
}

///|
test "GreenNode constructor computes text_len and hash" {
  let tok = GreenToken::new(RawKind(9), "x")
  let elem = GreenElement::Token(tok)
  let node = GreenNode::new(RawKind(20), [elem])
  inspect(node.text_len, content="1")
  inspect(node.hash != 0, content="true")
}

///|
test "GreenNode Eq: identical nodes are equal" {
  let a = GreenNode::new(RawKind(0), [])
  let b = GreenNode::new(RawKind(0), [])
  inspect(a == b, content="true")
}

///|
test "GreenNode Eq: different kind not equal" {
  let a = GreenNode::new(RawKind(0), [])
  let b = GreenNode::new(RawKind(1), [])
  inspect(a == b, content="false")
}

///|
test "GreenElement text_len and kind" {
  let tok = GreenToken::new(RawKind(9), "hello")
  let elem = GreenElement::Token(tok)
  inspect(elem.text_len(), content="5")
  inspect(elem.kind() == RawKind(9), content="true")
}

///|
test "has_errors detects error node kind" {
  let error_node_kind = RawKind(21)
  let error_token_kind = RawKind(12)
  let err = GreenNode::new(error_node_kind, [])
  inspect(err.has_errors(error_node_kind, error_token_kind), content="true")
}

///|
test "has_errors returns false for clean node" {
  let error_node_kind = RawKind(21)
  let error_token_kind = RawKind(12)
  let clean = GreenNode::new(RawKind(22), [])
  inspect(clean.has_errors(error_node_kind, error_token_kind), content="false")
}
```

**Step 2: Run to verify it fails**

```bash
moon test src/green-tree
```
Expected: FAIL — types not defined.

**Step 3: Implement `green_node.mbt`**

Create `src/green-tree/green_node.mbt`:
```moonbit
///|
/// Language-independent node kind (equivalent to rowan's RawSyntaxKind).
/// Each language defines its own enum and converts to/from RawKind via to_raw()/from_raw().
pub(all) type RawKind Int derive(Eq, Show, Hash)

///|
pub(all) struct GreenToken {
  kind : RawKind
  text : String
  hash : Int
} derive(Show)

///|
/// Create a GreenToken. Hash is computed from kind and text.
pub fn GreenToken::new(kind : RawKind, text : String) -> GreenToken {
  let RawKind(k) = kind
  let h = combine_hash(k, string_hash(text))
  { kind, text, hash: h }
}

///|
pub fn GreenToken::text_len(self : GreenToken) -> Int {
  self.text.length()
}

///|
impl Eq for GreenToken with op_equal(self, other) {
  if self.hash != other.hash {
    return false
  }
  self.kind == other.kind && self.text == other.text
}

///|
pub(all) enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
} derive(Show)

///|
pub fn GreenElement::text_len(self : GreenElement) -> Int {
  match self {
    Token(t) => t.text_len()
    Node(n) => n.text_len
  }
}

///|
pub fn GreenElement::kind(self : GreenElement) -> RawKind {
  match self {
    Token(t) => t.kind
    Node(n) => n.kind
  }
}

///|
impl Eq for GreenElement with op_equal(self, other) {
  match (self, other) {
    (Token(a), Token(b)) => a == b
    (Node(a), Node(b)) => a == b
    _ => false
  }
}

///|
pub(all) struct GreenNode {
  kind : RawKind
  children : Array[GreenElement]
  text_len : Int
  hash : Int
} derive(Show)

///|
/// Create a GreenNode. text_len and hash are computed from children.
pub fn GreenNode::new(
  kind : RawKind,
  children : Array[GreenElement],
) -> GreenNode {
  let RawKind(k) = kind
  let mut text_len = 0
  let mut h = k
  for child in children {
    text_len = text_len + child.text_len()
    h = combine_hash(h, child_hash(child))
  }
  { kind, children, text_len, hash: h }
}

///|
fn child_hash(elem : GreenElement) -> Int {
  match elem {
    Token(t) => t.hash
    Node(n) => n.hash
  }
}

///|
pub fn GreenNode::kind(self : GreenNode) -> RawKind {
  self.kind
}

///|
impl Eq for GreenNode with op_equal(self, other) {
  if self.hash != other.hash {
    return false
  }
  if self.kind != other.kind || self.children.length() != other.children.length() {
    return false
  }
  for i = 0; i < self.children.length(); i = i + 1 {
    if self.children[i] != other.children[i] {
      return false
    }
  }
  true
}

///|
/// Check if this green tree contains any error nodes or error tokens.
/// error_node_kind and error_token_kind are language-specific RawKind values.
pub fn GreenNode::has_errors(
  self : GreenNode,
  error_node_kind : RawKind,
  error_token_kind : RawKind,
) -> Bool {
  if self.kind == error_node_kind {
    return true
  }
  for elem in self.children {
    match elem {
      Token(t) => if t.kind == error_token_kind { return true }
      Node(n) => if n.has_errors(error_node_kind, error_token_kind) { return true }
    }
  }
  false
}
```

**Step 4: Run tests**

```bash
moon test src/green-tree
```
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add src/green-tree/green_node.mbt src/green-tree/green_node_test.mbt
git commit -m "feat(green-tree): add RawKind, GreenToken, GreenElement, GreenNode with hash-based Eq"
```

---

### Task 3: Implement `red_node.mbt`

**Files:**
- Create: `src/green-tree/red_node.mbt`
- Create: `src/green-tree/red_node_test.mbt`

**Step 1: Write the failing tests**

Create `src/green-tree/red_node_test.mbt`:
```moonbit
///|
test "RedNode::from_green creates root at offset 0" {
  let green = GreenNode::new(RawKind(22), [])
  let red = RedNode::from_green(green)
  inspect(red.start(), content="0")
  inspect(red.end(), content="0")
  inspect(red.kind() == RawKind(22), content="true")
}

///|
test "RedNode::children computes offsets" {
  // Build: SourceFile containing a GreenToken "hello"
  let tok = GreenToken::new(RawKind(9), "hello")
  let child_elem = GreenElement::Token(tok)
  let inner = GreenNode::new(RawKind(20), [child_elem])
  let root = GreenNode::new(RawKind(22), [GreenElement::Node(inner)])
  let red = RedNode::from_green(root)
  let children = red.children()
  inspect(children.length(), content="1")
  inspect(children[0].start(), content="0")
  inspect(children[0].end(), content="5")
}
```

**Step 2: Run to verify failure**

```bash
moon test src/green-tree
```
Expected: FAIL — `RedNode` not defined.

**Step 3: Implement `red_node.mbt`**

Create `src/green-tree/red_node.mbt`:
```moonbit
///|
pub struct RedNode {
  green : GreenNode
  parent : RedNode?
  offset : Int
}

///|
pub fn RedNode::new(
  green : GreenNode,
  parent : RedNode?,
  offset : Int,
) -> RedNode {
  { green, parent, offset }
}

///|
/// Create a root RedNode from a GreenNode (offset = 0, no parent).
pub fn RedNode::from_green(green : GreenNode) -> RedNode {
  RedNode::new(green, None, 0)
}

///|
pub fn RedNode::start(self : RedNode) -> Int {
  self.offset
}

///|
pub fn RedNode::end(self : RedNode) -> Int {
  self.offset + self.green.text_len
}

///|
pub fn RedNode::kind(self : RedNode) -> RawKind {
  self.green.kind
}

///|
pub fn RedNode::children(self : RedNode) -> Array[RedNode] {
  let result : Array[RedNode] = []
  for offset = self.offset, i = 0; i < self.green.children.length(); {
    match self.green.children[i] {
      Node(green_child) => {
        result.push(RedNode::new(green_child, Some(self), offset))
        continue offset + green_child.text_len, i + 1
      }
      Token(token) => continue offset + token.text_len(), i + 1
    }
  }
  result
}
```

**Step 4: Run tests**

```bash
moon test src/green-tree
```
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add src/green-tree/red_node.mbt src/green-tree/red_node_test.mbt
git commit -m "feat(green-tree): add RedNode with RawKind-typed kind()"
```

---

### Task 4: Implement `event.mbt`

**Files:**
- Create: `src/green-tree/event.mbt`
- Create: `src/green-tree/event_test.mbt`

**Step 1: Write the failing tests**

Create `src/green-tree/event_test.mbt`:
```moonbit
///|
test "build_tree: single token produces root node" {
  let events = [
    ParseEvent::Token(RawKind(10), "42"),
  ]
  let root = build_tree(events, RawKind(22))
  inspect(root.kind == RawKind(22), content="true")
  inspect(root.children.length(), content="1")
  inspect(root.text_len, content="2")
}

///|
test "build_tree: nested StartNode/FinishNode" {
  let events = [
    ParseEvent::StartNode(RawKind(19)), // IntLiteral
    ParseEvent::Token(RawKind(10), "5"),
    ParseEvent::FinishNode,
  ]
  let root = build_tree(events, RawKind(22))
  inspect(root.kind == RawKind(22), content="true")
  inspect(root.children.length(), content="1")
  let child = match root.children[0] {
    GreenElement::Node(n) => n
    GreenElement::Token(_) => abort("expected node")
  }
  inspect(child.kind == RawKind(19), content="true")
  inspect(child.text_len, content="1")
}

///|
test "EventBuffer mark and start_at" {
  let buf = EventBuffer::new()
  let m = buf.mark()
  buf.push(ParseEvent::Token(RawKind(9), "x"))
  buf.start_at(m, RawKind(20)) // retroactively set mark to VarRef
  inspect(buf.events[m] == ParseEvent::StartNode(RawKind(20)), content="true")
}

///|
test "Tombstone events are ignored by build_tree" {
  let events = [
    ParseEvent::Tombstone,
    ParseEvent::Token(RawKind(10), "1"),
  ]
  let root = build_tree(events, RawKind(22))
  inspect(root.children.length(), content="1")
}
```

**Step 2: Run to verify failure**

```bash
moon test src/green-tree
```
Expected: FAIL.

**Step 3: Implement `event.mbt`**

Create `src/green-tree/event.mbt`:
```moonbit
///|
pub(all) enum ParseEvent {
  StartNode(RawKind)
  FinishNode
  Token(RawKind, String)
  Tombstone
} derive(Show, Eq)

///|
pub struct EventBuffer {
  pub events : Array[ParseEvent]
}

///|
pub fn EventBuffer::new() -> EventBuffer {
  { events: [] }
}

///|
pub fn EventBuffer::push(self : EventBuffer, event : ParseEvent) -> Unit {
  self.events.push(event)
}

///|
/// Reserve a slot and return its index. Used for retroactive StartNode placement.
pub fn EventBuffer::mark(self : EventBuffer) -> Int {
  let index = self.events.length()
  self.events.push(Tombstone)
  index
}

///|
/// Retroactively fill a Tombstone slot with StartNode(kind).
pub fn EventBuffer::start_at(
  self : EventBuffer,
  mark : Int,
  kind : RawKind,
) -> Unit {
  self.events[mark] = StartNode(kind)
}

///|
/// Build a green tree from a flat event stream.
/// root_kind is the kind of the implicit root node (e.g., SourceFile).
pub fn build_tree(events : Array[ParseEvent], root_kind : RawKind) -> GreenNode {
  let stack : Array[Array[GreenElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      StartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      FinishNode => {
        let children = match stack.pop() {
          Some(c) => c
          None =>
            abort(
              "build_tree: unbalanced FinishNode — no matching StartNode",
            )
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None => abort("build_tree: kind stack underflow on FinishNode")
        }
        let node = GreenNode::new(kind, children)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort("build_tree: parent stack empty when attaching node")
        }
      }
      Token(kind, text) => {
        let token = GreenToken::new(kind, text)
        match stack.last() {
          Some(top) => top.push(GreenElement::Token(token))
          None => abort("build_tree: stack empty when adding token")
        }
      }
      Tombstone => ()
    }
  }
  let children = match stack.pop() {
    Some(c) => c
    None => abort("build_tree: stack empty at end — mismatched events")
  }
  GreenNode::new(root_kind, children)
}
```

**Step 4: Run tests**

```bash
moon test src/green-tree
```
Expected: All tests PASS.

**Step 5: Verify zero dependencies**

```bash
cat src/green-tree/moon.pkg.json
```
Expected output: `{}`

**Step 6: Commit**

```bash
git add src/green-tree/event.mbt src/green-tree/event_test.mbt
git commit -m "feat(green-tree): add ParseEvent, EventBuffer, and parameterized build_tree"
```

---

### Task 5: Update `syntax/` — add `to_raw`/`from_raw`, remove moved code

**Files:**
- Create: `src/syntax/syntax_kind.mbt`
- Modify: `src/syntax/moon.pkg.json`
- Delete: `src/syntax/green_tree.mbt` (content moved to green-tree)
- Delete: `src/syntax/red_tree.mbt` (content moved to green-tree)
- Delete: `src/syntax/parse_events.mbt` (content moved to green-tree)

> **Note:** Do NOT delete these files until all downstream consumers have been updated (Tasks 6–9). Delete them only after Task 9.

**Step 1: Update `src/syntax/moon.pkg.json`**

```json
{
  "import": [
    "dowdiness/parser/green-tree"
  ]
}
```

**Step 2: Add `to_raw`/`from_raw` to the existing `green_tree.mbt`**

Open `src/syntax/green_tree.mbt` and append at the end (before the file is deleted later):

```moonbit
///|
pub fn SyntaxKind::to_raw(self : SyntaxKind) -> @green_tree.RawKind {
  let n : Int = match self {
    LambdaToken     => 0
    DotToken        => 1
    LeftParenToken  => 2
    RightParenToken => 3
    PlusToken       => 4
    MinusToken      => 5
    IfKeyword       => 6
    ThenKeyword     => 7
    ElseKeyword     => 8
    IdentToken      => 9
    IntToken        => 10
    WhitespaceToken => 11
    ErrorToken      => 12
    EofToken        => 13
    LambdaExpr      => 14
    AppExpr         => 15
    BinaryExpr      => 16
    IfExpr          => 17
    ParenExpr       => 18
    IntLiteral      => 19
    VarRef          => 20
    ErrorNode       => 21
    SourceFile      => 22
  }
  @green_tree.RawKind(n)
}

///|
pub fn SyntaxKind::from_raw(raw : @green_tree.RawKind) -> SyntaxKind {
  let @green_tree.RawKind(n) = raw
  match n {
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

**Step 3: Verify syntax compiles with both old types and new conversions**

```bash
moon check
```
Expected: no errors (existing code still uses `@syntax.GreenNode` etc., and they still exist).

**Step 4: Commit (intermediate — old files still present)**

```bash
git add src/syntax/moon.pkg.json src/syntax/green_tree.mbt
git commit -m "feat(syntax): add to_raw/from_raw conversions using @green_tree.RawKind"
```

---

### Task 6: Update `parser/moon.pkg.json` and `green_parser.mbt`

**Files:**
- Modify: `src/parser/moon.pkg.json`
- Modify: `src/parser/green_parser.mbt`

**Step 1: Add `green-tree` to parser imports**

Update `src/parser/moon.pkg.json`:
```json
{
  "import": [
    "dowdiness/parser/token",
    "dowdiness/parser/range",
    "dowdiness/parser/term",
    "dowdiness/parser/lexer",
    "dowdiness/parser/syntax",
    "dowdiness/parser/green-tree",
    "moonbitlang/core/strconv"
  ],
  "test-import": [
    "moonbitlang/core/quickcheck"
  ]
}
```

**Step 2: Update `green_parser.mbt`**

At the top of `green_parser.mbt`, the `GreenParser` struct and helper functions use `@syntax.*` for tree types and events. Replace all uses:

Add a local helper function after the `max_errors` let binding:
```moonbit
///|
/// Convert SyntaxKind to RawKind for green-tree events.
fn raw(kind : @syntax.SyntaxKind) -> @green_tree.RawKind {
  kind.to_raw()
}
```

Replace type annotations in the struct:
- `events : @syntax.EventBuffer` → `events : @green_tree.EventBuffer`

Replace in `GreenParser::new` and `GreenParser::new_with_cursor`:
- `@syntax.EventBuffer::new()` → `@green_tree.EventBuffer::new()`

Replace in `GreenParser::start_node`:
- `self.events.push(@syntax.StartNode(kind))` → `self.events.push(@green_tree.StartNode(raw(kind)))`

Replace in `GreenParser::finish_node`:
- `self.events.push(@syntax.FinishNode)` → `self.events.push(@green_tree.FinishNode)`

Replace in `GreenParser::emit_whitespace_before`:
- `self.events.push(@syntax.ParseEvent::Token(@syntax.WhitespaceToken, ...))` → `self.events.push(@green_tree.ParseEvent::Token(raw(@syntax.WhitespaceToken), ...))`

Replace in `GreenParser::emit_token`:
- `self.events.push(@syntax.ParseEvent::Token(kind, text))` → `self.events.push(@green_tree.ParseEvent::Token(raw(kind), text))`

Replace in `GreenParser::emit_reused_node_events`:
- `self.events.push(@syntax.StartNode(node.kind))` → `self.events.push(@green_tree.StartNode(node.kind))`
  *(Note: `node.kind` is already `RawKind` after Task 2)*
- `@syntax.GreenElement::Token(t)` → `@green_tree.GreenElement::Token(t)`
- `@syntax.GreenElement::Node(n)` → `@green_tree.GreenElement::Node(n)`
- `self.events.push(@syntax.ParseEvent::Token(t.kind, t.text))` → `self.events.push(@green_tree.ParseEvent::Token(t.kind, t.text))`
- `self.events.push(@syntax.FinishNode)` → `self.events.push(@green_tree.FinishNode)`

Replace in `count_tokens_in_green`:
- `@syntax.GreenNode` → `@green_tree.GreenNode`
- `@syntax.GreenElement::Token(t)` → `@green_tree.GreenElement::Token(t)`
- `t.kind != @syntax.WhitespaceToken` → `t.kind != @syntax.WhitespaceToken.to_raw()`
- `@syntax.GreenElement::Node(n)` → `@green_tree.GreenElement::Node(n)`

Replace in `GreenParser::bump_error`:
- `self.events.push(@syntax.ParseEvent::Token(@syntax.ErrorToken, text))` → `self.events.push(@green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), text))`

Replace in `GreenParser::expect`:
- `self.events.push(@syntax.ParseEvent::Token(@syntax.ErrorToken, ""))` → `self.events.push(@green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), ""))`

Replace all 3 `build_tree` calls:
```moonbit
// Old:
let tree = @syntax.build_tree(parser.events.events)

// New:
let tree = @green_tree.build_tree(parser.events.events, raw(@syntax.SourceFile))
```

Replace in `parse_source_file` (2 occurrences of whitespace token emit):
- `@syntax.ParseEvent::Token(@syntax.WhitespaceToken, ...)` → `@green_tree.ParseEvent::Token(raw(@syntax.WhitespaceToken), ...)`

Replace error node events in `parse_source_file` and `parse_atom`:
- `@syntax.ParseEvent::Token(@syntax.ErrorToken, "")` → `@green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), "")`

Change return types:
- `pub fn parse_green(source: String) -> @syntax.GreenNode raise` → `@green_tree.GreenNode`
- `pub fn parse_green_recover(...) -> (@syntax.GreenNode, ...)` → `@green_tree.GreenNode`
- `pub fn parse_green_with_cursor(...) -> (@syntax.GreenNode, ...)` → `@green_tree.GreenNode`
- `pub fn parse_green_recover_with_tokens(...) -> (@syntax.GreenNode, ...)` → `@green_tree.GreenNode`

**Step 3: Verify it compiles**

```bash
moon check
```
Expected: no errors. (Other downstream files still compile using old `@syntax` types.)

**Step 4: Run tests**

```bash
moon test src/parser
```
Expected: Some snapshot tests may FAIL because `inspect(green.kind, ...)` now shows `RawKind(22)` instead of `"SourceFile"`. Fix in next task.

**Step 5: Commit what compiles**

```bash
git add src/parser/moon.pkg.json src/parser/green_parser.mbt
git commit -m "feat(parser): migrate green_parser to use @green_tree events and RawKind"
```

---

### Task 7: Update `parser/reuse_cursor.mbt`

**Files:**
- Modify: `src/parser/reuse_cursor.mbt`

This file uses `@syntax.GreenNode`, `@syntax.GreenElement`, `@syntax.SyntaxKind` throughout. The strategy: all tree types switch to `@green_tree`, `SyntaxKind` comparisons convert via `.to_raw()`.

**Step 1: Update `CursorFrame`**

```moonbit
struct CursorFrame {
  node : @green_tree.GreenNode
  mut child_index : Int
  start_offset : Int
}
```

**Step 2: Update `ReuseCursor` struct**

```moonbit
pub struct ReuseCursor {
  stack : Array[CursorFrame]
  mut current_offset : Int
  damaged_range : @range.Range
  tokens : Array[@token.TokenInfo]
  reuse_globally_disabled : Bool
}
```

**Step 3: Update `ReuseCursor::new`**

Parameter `old_tree : @green_tree.GreenNode`. The rest is unchanged.

**Step 4: Update `ReuseCursor::old_tree` return type**

```moonbit
pub fn ReuseCursor::old_tree(self : ReuseCursor) -> @green_tree.GreenNode {
  self.stack[0].node
}
```

**Step 5: Update `count_tokens_in_node`**

```moonbit
fn count_tokens_in_node(node : @green_tree.GreenNode) -> Int {
  let mut count = 0
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() { count = count + 1 }
      @green_tree.GreenElement::Node(n) => count = count + count_tokens_in_node(n)
    }
  }
  count
}
```

**Step 6: Update `first_token_text`**

```moonbit
fn first_token_text(node : @green_tree.GreenNode) -> String? {
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() { return Some(t.text) }
      @green_tree.GreenElement::Node(n) => {
        let result = first_token_text(n)
        if result is Some(_) { return result }
      }
    }
  }
  None
}
```

**Step 7: Update `first_token_kind` — returns `@green_tree.RawKind?`**

```moonbit
fn first_token_kind(node : @green_tree.GreenNode) -> @green_tree.RawKind? {
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() { return Some(t.kind) }
      @green_tree.GreenElement::Node(n) => {
        let result = first_token_kind(n)
        if result is Some(_) { return result }
      }
    }
  }
  None
}
```

**Step 8: Update `syntax_kind_to_token_kind` — takes `@green_tree.RawKind`**

```moonbit
fn syntax_kind_to_token_kind(kind : @green_tree.RawKind) -> @token.Token? {
  match @syntax.SyntaxKind::from_raw(kind) {
    @syntax.LambdaToken     => Some(@token.Lambda)
    @syntax.DotToken        => Some(@token.Dot)
    @syntax.LeftParenToken  => Some(@token.LeftParen)
    @syntax.RightParenToken => Some(@token.RightParen)
    @syntax.PlusToken       => Some(@token.Plus)
    @syntax.MinusToken      => Some(@token.Minus)
    @syntax.IfKeyword       => Some(@token.If)
    @syntax.ThenKeyword     => Some(@token.Then)
    @syntax.ElseKeyword     => Some(@token.Else)
    _ => None
  }
}
```

**Step 9: Update `token_matches_syntax_kind` — takes `@green_tree.RawKind`**

```moonbit
fn token_matches_syntax_kind(
  token : @token.Token,
  text : String,
  kind : @green_tree.RawKind,
) -> Bool {
  match @syntax.SyntaxKind::from_raw(kind) {
    @syntax.IdentToken =>
      match token {
        @token.Identifier(name) => name == text
        _ => false
      }
    @syntax.IntToken =>
      match token {
        @token.Integer(_) => true
        _ => false
      }
    _ =>
      match syntax_kind_to_token_kind(kind) {
        Some(expected) => token == expected
        None => false
      }
  }
}
```

**Step 10: Update `last_token_kind` — returns `@green_tree.RawKind?`**

```moonbit
fn last_token_kind(node : @green_tree.GreenNode) -> @green_tree.RawKind? {
  let children = node.children
  for i = children.length() - 1; i >= 0; i = i - 1 {
    match children[i] {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() { return Some(t.kind) }
      @green_tree.GreenElement::Node(n) => {
        let result = last_token_kind(n)
        if result is Some(_) { return result }
      }
    }
  }
  None
}
```

**Step 11: Update `trailing_context_matches`**

In `trailing_context_matches`, the match on `last_kind` now uses `@syntax.SyntaxKind::from_raw`:
```moonbit
match @syntax.SyntaxKind::from_raw(last_kind) {
  @syntax.IdentToken =>
    match after_token.token {
      @token.Identifier(_) => false
      _ => true
    }
  @syntax.IntToken =>
    match after_token.token {
      @token.Integer(_) => false
      _ => true
    }
  _ => true
}
```

**Step 12: Update `element_width`**

```moonbit
fn element_width(elem : @green_tree.GreenElement) -> Int {
  match elem {
    @green_tree.GreenElement::Token(t) => t.text_len()
    @green_tree.GreenElement::Node(n) => n.text_len
  }
}
```

**Step 13: Update `seek_node_at` — takes `@green_tree.RawKind` for `expected_kind`**

Change signature:
```moonbit
fn ReuseCursor::seek_node_at(
  self : ReuseCursor,
  target_offset : Int,
  expected_kind : @green_tree.RawKind,
) -> (@green_tree.GreenNode, Int)? {
```

Internal `node.kind == expected_kind` comparisons now work directly since both are `RawKind`.

Change match arms from `@syntax.GreenElement::Node/Token` to `@green_tree.GreenElement::Node/Token`.

**Step 14: Update `try_reuse` — takes `@green_tree.RawKind`**

```moonbit
pub fn ReuseCursor::try_reuse(
  self : ReuseCursor,
  expected_kind : @green_tree.RawKind,
  byte_offset : Int,
  token_pos : Int,
) -> @green_tree.GreenNode? {
```

**Step 15: Update `advance_past`**

```moonbit
pub fn ReuseCursor::advance_past(self : ReuseCursor, node : @green_tree.GreenNode) -> Unit {
  self.current_offset = self.current_offset + node.text_len
}
```

**Step 16: Update `try_reuse` call sites in `green_parser.mbt`**

In `GreenParser::try_reuse` (the one in green_parser.mbt that calls `cursor.try_reuse`):
```moonbit
// Old:
match cursor.try_reuse(expected_kind, byte_offset, self.position) {
// expected_kind was @syntax.SyntaxKind

// New — the parameter is already @green_tree.RawKind since parse_atom calls:
if self.try_reuse(@syntax.IntLiteral) → if self.try_reuse(raw(@syntax.IntLiteral))
```

In `parse_atom`, change all `try_reuse(@syntax.XxxKind)` calls to `try_reuse(raw(@syntax.XxxKind))`:
```moonbit
if self.try_reuse(raw(@syntax.IntLiteral)) { return }
if self.try_reuse(raw(@syntax.VarRef))     { return }
if self.try_reuse(raw(@syntax.LambdaExpr)) { return }
if self.try_reuse(raw(@syntax.IfExpr))     { return }
if self.try_reuse(raw(@syntax.ParenExpr))  { return }
```

And in `GreenParser::try_reuse` itself, change `expected_kind` type to `@green_tree.RawKind`.

**Step 17: Verify compilation**

```bash
moon check
```
Expected: no errors.

**Step 18: Commit**

```bash
git add src/parser/reuse_cursor.mbt src/parser/green_parser.mbt
git commit -m "feat(parser): migrate reuse_cursor to @green_tree types and RawKind comparisons"
```

---

### Task 8: Update `green_convert.mbt` and parser test files

**Files:**
- Modify: `src/parser/green_convert.mbt`
- Modify: `src/parser/green_tree_test.mbt`
- Modify: `src/parser/reuse_cursor_test.mbt`

**Step 1: Update `green_convert.mbt` — `convert_red` kind matching**

`convert_red` receives a `@syntax.RedNode`. After changes, `red.green.kind` is `RawKind`.
All `match g.kind { @syntax.IntLiteral => ... }` become:
```moonbit
match @syntax.SyntaxKind::from_raw(g.kind) {
  IntLiteral => ...
  VarRef => ...
  // etc.
}
```

Also update type annotations:
- `green : @syntax.GreenNode` → `@green_tree.GreenNode`
- `@syntax.GreenElement::Token(t)` → `@green_tree.GreenElement::Token(t)`
- `@syntax.GreenElement::Node(_)` → `@green_tree.GreenElement::Node(_)`
- `t.kind == @syntax.IntToken` → `t.kind == @syntax.IntToken.to_raw()`
- `t.kind == @syntax.IdentToken` → `t.kind == @syntax.IdentToken.to_raw()`
- `t.kind != @syntax.WhitespaceToken` → `t.kind != @syntax.WhitespaceToken.to_raw()`
- `t.kind == @syntax.PlusToken` → `t.kind == @syntax.PlusToken.to_raw()`
- `t.kind == @syntax.MinusToken` → `t.kind == @syntax.MinusToken.to_raw()`

Update `green_to_term_node`, `green_to_term`, `parse_green_to_term_node` to use `@green_tree.GreenNode`.

`@syntax.RedNode::new(green, None, offset)` — `RedNode` is now in `@green_tree`:
```moonbit
// Old:
let red = @syntax.RedNode::new(green, None, offset)
// New:
let red = @green_tree.RedNode::new(green, None, offset)
```

**Step 2: Update `green_tree_test.mbt`**

The key issue: `inspect(green.kind, content="SourceFile")` — `green.kind` is now `RawKind(22)`.
Change all such inspects to use `from_raw`:
```moonbit
// Old:
inspect(green.kind, content="SourceFile")
// New:
inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
```

Do the same for all `inspect(child.kind, content="IntLiteral")` etc.

Also update all `@syntax.GreenElement::Node/Token` pattern matches to `@green_tree.*`.

**Step 3: Update `reuse_cursor_test.mbt`**

```moonbit
// Old:
inspect(cursor.old_tree().kind, content="SourceFile")
// New:
inspect(@syntax.SyntaxKind::from_raw(cursor.old_tree().kind), content="SourceFile")
```

The `try_reuse` calls already receive `RawKind` from `n.kind` (green element's kind), so they work as-is.

**Step 4: Run tests**

```bash
moon test src/parser
```
Expected: PASS (snapshots may need update — see next step).

**Step 5: Update snapshots if needed**

If snapshot content mismatches, run:
```bash
moon test src/parser --update
```
Then review `git diff` to confirm only expected snapshot strings changed.

**Step 6: Verify**

```bash
moon check && moon test
```
Expected: all PASS.

**Step 7: Commit**

```bash
git add src/parser/green_convert.mbt src/parser/green_tree_test.mbt src/parser/reuse_cursor_test.mbt
git commit -m "feat(parser): update green_convert and tests to use @green_tree types"
```

---

### Task 9: Update `incremental/` and remove old `syntax/` files

**Files:**
- Modify: `src/incremental/moon.pkg.json`
- Modify: `src/incremental/incremental_parser.mbt`
- Modify: `src/incremental/perf_instrumentation.mbt`
- Delete: `src/syntax/green_tree.mbt`
- Delete: `src/syntax/red_tree.mbt`
- Delete: `src/syntax/parse_events.mbt`
- Create: `src/syntax/syntax_kind.mbt` (consolidate remaining syntax code)

**Step 1: Add `green-tree` to incremental imports**

Update `src/incremental/moon.pkg.json`:
```json
{
  "import": [
    "dowdiness/parser/token",
    "dowdiness/parser/range",
    "dowdiness/parser/term",
    "dowdiness/parser/edit",
    "dowdiness/parser/lexer",
    "dowdiness/parser/syntax",
    "dowdiness/parser/green-tree",
    {
      "path": "dowdiness/parser/parser",
      "alias": "parse"
    }
  ],
  "test-import": []
}
```

**Step 2: Update `incremental_parser.mbt`**

Change:
```moonbit
// Old:
mut green_tree : @syntax.GreenNode?

// New:
mut green_tree : @green_tree.GreenNode?
```

**Step 3: Update `perf_instrumentation.mbt`**

Change:
```moonbit
// Old:
pub fn count_tokens_in_node_instrumented(node : @syntax.GreenNode) -> Int {
  for child in node.children {
    match child {
      @syntax.GreenElement::Token(t) => if t.kind != @syntax.WhitespaceToken { ... }
      @syntax.GreenElement::Node(n) => ...

// New:
pub fn count_tokens_in_node_instrumented(node : @green_tree.GreenNode) -> Int {
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() { ... }
      @green_tree.GreenElement::Node(n) => ...
```

**Step 4: Verify incremental compiles**

```bash
moon check
```
Expected: no errors.

**Step 5: Create `src/syntax/syntax_kind.mbt`**

Move just the `SyntaxKind` enum, `is_token`, `to_raw`, and `from_raw` into a new file
`src/syntax/syntax_kind.mbt`. This is the final state of the syntax package.

The content is: the `SyntaxKind` enum (with `derive(Show, Eq)`), `SyntaxKind::is_token`,
`SyntaxKind::to_raw`, and `SyntaxKind::from_raw` — copied from `green_tree.mbt` (for the enum)
and the conversions added in Task 5.

**Step 6: Delete the three old syntax files**

```bash
rm src/syntax/green_tree.mbt src/syntax/red_tree.mbt src/syntax/parse_events.mbt
```

**Step 7: Run `moon check`**

```bash
moon check
```
Expected: no errors. If there are any remaining `@syntax.GreenNode` references elsewhere, fix them now.

**Step 8: Run full test suite**

```bash
moon test
```
Expected: all tests PASS.

**Step 9: Update interfaces**

```bash
moon info && moon fmt
```

**Step 10: Commit**

```bash
git add src/incremental/ src/syntax/
git rm src/syntax/green_tree.mbt src/syntax/red_tree.mbt src/syntax/parse_events.mbt
git add src/syntax/syntax_kind.mbt
git commit -m "feat(syntax,incremental): finalize green-tree extraction — remove old syntax files, update incremental"
```

---

### Task 10: Final verification and `moon info`

**Step 1: Verify zero dependencies on `green-tree`**

```bash
cat src/green-tree/moon.pkg.json
```
Expected: `{}`

**Step 2: Verify `syntax` imports only `green-tree`**

```bash
cat src/syntax/moon.pkg.json
```
Expected:
```json
{
  "import": [
    "dowdiness/parser/green-tree"
  ]
}
```

**Step 3: Full check and test**

```bash
moon check && moon test
```
Expected: all PASS, no errors.

**Step 4: Update `.mbti` interface files and format**

```bash
moon info && moon fmt
```

**Step 5: Review interface changes**

```bash
git diff '*.mbti'
```
Expected changes:
- `green-tree/pkg.generated.mbti` — new file with `RawKind`, `GreenNode`, `GreenToken`, `GreenElement`, `RedNode`, `ParseEvent`, `EventBuffer`, `build_tree`, hash functions
- `syntax/pkg.generated.mbti` — now only contains `SyntaxKind`, `is_token`, `to_raw`, `from_raw`
- `parser/pkg.generated.mbti` — return types updated to `@green_tree.GreenNode`

**Step 6: Run benchmarks to confirm no regression**

```bash
moon bench --release
```
Expected: comparable or better performance (hash-based Eq is O(1) vs deep structural).

**Step 7: Final commit**

```bash
git add .
git commit -m "chore: update .mbti interfaces after green-tree extraction"
```

---

## Summary

| Task | What changes | Risk |
|------|-------------|------|
| 1 | New `hash.mbt` | Low — new file |
| 2 | New `green_node.mbt` | Low — new file |
| 3 | New `red_node.mbt` | Low — new file |
| 4 | New `event.mbt` | Low — new file |
| 5 | `syntax/` gets `to_raw`/`from_raw` | Low — additive |
| 6 | `green_parser.mbt` event types | Medium — many substitutions |
| 7 | `reuse_cursor.mbt` types | High — most complex file |
| 8 | `green_convert.mbt` + tests | Medium — kind matching pattern |
| 9 | `incremental/` + delete old files | Medium — final cleanup |
| 10 | Verification | Low |

**The only behavioral change** is hash-based `Eq` on `GreenNode`/`GreenToken` — same results, O(1) fast path for equal nodes. All other changes are purely structural.
