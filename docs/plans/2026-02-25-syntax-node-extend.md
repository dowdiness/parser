# Extend SyntaxNode — Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `SyntaxToken`, `SyntaxElement`, token-iteration methods, `tight_span`, `find_at`, `Show`, and `Debug` to `seam/syntax_node.mbt` so that no caller ever needs to reach through `.cst` directly.

**Architecture:** All new code lives in `seam/syntax_node.mbt`. Tests go in `seam/syntax_node_wbtest.mbt` (whitebox — imports package internals directly). `.cst` stays public; making it private is Phase 2. No other files change.

**Tech Stack:** MoonBit · `moon test` (from `seam/` dir) · `moon info && moon fmt` before final commit

---

### Conventions to know

- Every top-level definition is preceded by `///|` on its own line (block separator).
- Tests are `test "description" { ... }` blocks inside `*_wbtest.mbt`.
- Snapshot assertions: `inspect(expr, content="expected string")`.
- Labelled optional parameters use `~` suffix and `= default`: `trivia_kind~ : RawKind? = None`.
- Run tests from `seam/` directory: `cd /path/to/parser/seam && moon test`.

---

### Task 1: Define `Debug` trait + `SyntaxToken` struct

`Debug` is not a standard MoonBit trait — define it locally in `seam/`.

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`

**Step 1: Write the failing tests**

Add to `seam/syntax_node_wbtest.mbt`:

```moonbit
///|
test "SyntaxToken::start and end" {
  let tok = CstToken::new(RawKind(9), "hello")
  let st = SyntaxToken::new(tok, 3)
  inspect(st.start(), content="3")
  inspect(st.end(), content="8")
}

///|
test "SyntaxToken::kind and text" {
  let tok = CstToken::new(RawKind(9), "foo")
  let st = SyntaxToken::new(tok, 0)
  inspect(st.kind() == RawKind(9), content="true")
  inspect(st.text(), content="foo")
}

///|
test "SyntaxToken Show" {
  let tok = CstToken::new(RawKind(9), "foo")
  let st = SyntaxToken::new(tok, 3)
  inspect(st, content="SyntaxToken@[3,6)")
}

///|
test "SyntaxToken Debug" {
  let tok = CstToken::new(RawKind(9), "foo")
  let st = SyntaxToken::new(tok, 3)
  inspect(st.debug_string(), content="SyntaxToken { kind: RawKind(9), offset: 3, text: \"foo\" }")
}
```

**Step 2: Run to verify failure**

```bash
cd /path/to/parser/seam && moon test
```
Expected: compile error — `SyntaxToken` not defined.

**Step 3: Implement in `seam/syntax_node.mbt`**

Add before the existing `SyntaxNode` struct:

```moonbit
///|
/// Structural debug representation trait.
/// Produces verbose output suitable for debugging (not display).
pub trait Debug {
  debug_string(Self) -> String
}

///|
/// Ephemeral positioned view over a `CstToken`.
/// Mirrors `SyntaxNode` but for leaf tokens.
pub struct SyntaxToken {
  cst : CstToken
  offset : Int
}

///|
pub fn SyntaxToken::new(cst : CstToken, offset : Int) -> SyntaxToken {
  { cst, offset }
}

///|
pub fn SyntaxToken::start(self : SyntaxToken) -> Int {
  self.offset
}

///|
pub fn SyntaxToken::end(self : SyntaxToken) -> Int {
  self.offset + self.cst.text_len()
}

///|
pub fn SyntaxToken::kind(self : SyntaxToken) -> RawKind {
  self.cst.kind
}

///|
pub fn SyntaxToken::text(self : SyntaxToken) -> String {
  self.cst.text
}

///|
/// Show: compact form — "SyntaxToken@[start,end)"
pub impl Show for SyntaxToken with output(self, logger) {
  logger.write_string("SyntaxToken@[")
  logger.write_string(self.start().to_string())
  logger.write_string(",")
  logger.write_string(self.end().to_string())
  logger.write_string(")")
}

///|
/// Debug: structural form — "SyntaxToken { kind: ..., offset: ..., text: ... }"
pub impl Debug for SyntaxToken with debug_string(self) {
  "SyntaxToken { kind: " +
  self.cst.kind.to_string() +
  ", offset: " +
  self.offset.to_string() +
  ", text: \"" +
  self.cst.text +
  "\" }"
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: all 4 new tests PASS.

**Step 5: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "feat(seam): add Debug trait and SyntaxToken positioned token view"
```

---

### Task 2: Add `SyntaxElement` enum

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`

**Step 1: Write the failing test**

```moonbit
///|
test "SyntaxElement wraps node and token" {
  let tok = CstToken::new(RawKind(9), "x")
  let st = SyntaxToken::new(tok, 5)
  let elem_tok = SyntaxElement::Token(st)
  inspect(elem_tok.start(), content="5")
  inspect(elem_tok.end(), content="6")

  let cst = CstNode::new(RawKind(20), [])
  let sn = SyntaxNode::from_cst(cst)
  let elem_node = SyntaxElement::Node(sn)
  inspect(elem_node.start(), content="0")
}
```

**Step 2: Run to verify failure**

```bash
cd /path/to/parser/seam && moon test
```
Expected: compile error — `SyntaxElement` not defined.

**Step 3: Implement** — add to `seam/syntax_node.mbt` after `SyntaxToken`:

```moonbit
///|
/// A child element — either an interior node or a leaf token, both positioned.
pub(all) enum SyntaxElement {
  Node(SyntaxNode)
  Token(SyntaxToken)
}

///|
pub fn SyntaxElement::start(self : SyntaxElement) -> Int {
  match self {
    Node(n) => n.start()
    Token(t) => t.start()
  }
}

///|
pub fn SyntaxElement::end(self : SyntaxElement) -> Int {
  match self {
    Node(n) => n.end()
    Token(t) => t.end()
  }
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: PASS.

**Step 5: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "feat(seam): add SyntaxElement positioned union type"
```

---

### Task 3: Add `all_children()` and `tokens()`

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`

**Step 1: Write the failing tests**

```moonbit
///|
test "SyntaxNode::all_children includes tokens and nodes" {
  let tok = CstToken::new(RawKind(9), "hi")
  let inner = CstNode::new(RawKind(20), [])
  let root = CstNode::new(
    RawKind(22),
    [CstElement::Token(tok), CstElement::Node(inner)],
  )
  let sn = SyntaxNode::from_cst(root)
  let children = sn.all_children()
  inspect(children.length(), content="2")
  inspect(children[0].start(), content="0")
  inspect(children[0].end(), content="2")
  inspect(children[1].start(), content="2")
}

///|
test "SyntaxNode::tokens returns only leaf tokens with offsets" {
  let t1 = CstToken::new(RawKind(9), "ab")
  let t2 = CstToken::new(RawKind(10), "cd")
  let inner = CstNode::new(RawKind(20), [CstElement::Token(t2)])
  let root = CstNode::new(
    RawKind(22),
    [CstElement::Token(t1), CstElement::Node(inner)],
  )
  let sn = SyntaxNode::from_cst(root)
  let toks = sn.tokens()
  inspect(toks.length(), content="1")
  inspect(toks[0].text(), content="ab")
  inspect(toks[0].start(), content="0")
}
```

**Step 2: Run to verify failure**

Expected: compile error — methods not defined.

**Step 3: Implement** — add to `seam/syntax_node.mbt`:

```moonbit
///|
/// All direct children as `SyntaxElement`s, preserving token order.
pub fn SyntaxNode::all_children(self : SyntaxNode) -> Array[SyntaxElement] {
  let result : Array[SyntaxElement] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Node(child_cst) => {
        result.push(
          SyntaxElement::Node(SyntaxNode::new(child_cst, Some(self), offset)),
        )
        offset = offset + child_cst.text_len
      }
      CstElement::Token(tok) => {
        result.push(SyntaxElement::Token(SyntaxToken::new(tok, offset)))
        offset = offset + tok.text_len()
      }
    }
  }
  result
}

///|
/// Direct leaf tokens only (child nodes are skipped).
pub fn SyntaxNode::tokens(self : SyntaxNode) -> Array[SyntaxToken] {
  let result : Array[SyntaxToken] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        result.push(SyntaxToken::new(tok, offset))
        offset = offset + tok.text_len()
      }
      CstElement::Node(child) => offset = offset + child.text_len
    }
  }
  result
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: PASS.

**Step 5: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "feat(seam): add SyntaxNode::all_children and tokens"
```

---

### Task 4: Add `find_token()` and `tokens_of_kind()`

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`

**Step 1: Write the failing tests**

```moonbit
///|
test "SyntaxNode::find_token returns first matching token" {
  let ident = CstToken::new(RawKind(9), "x")
  let dot = CstToken::new(RawKind(2), ".")
  let root = CstNode::new(
    RawKind(22),
    [CstElement::Token(ident), CstElement::Token(dot)],
  )
  let sn = SyntaxNode::from_cst(root)
  match sn.find_token(RawKind(2)) {
    Some(t) => inspect(t.text(), content=".")
    None => inspect("none", content=".")
  }
  match sn.find_token(RawKind(99)) {
    Some(_) => inspect("found", content="none")
    None => inspect("none", content="none")
  }
}

///|
test "SyntaxNode::tokens_of_kind collects all matching tokens" {
  let plus1 = CstToken::new(RawKind(5), "+")
  let ident = CstToken::new(RawKind(9), "x")
  let plus2 = CstToken::new(RawKind(5), "+")
  let root = CstNode::new(
    RawKind(22),
    [
      CstElement::Token(plus1),
      CstElement::Token(ident),
      CstElement::Token(plus2),
    ],
  )
  let sn = SyntaxNode::from_cst(root)
  let ops = sn.tokens_of_kind(RawKind(5))
  inspect(ops.length(), content="2")
  inspect(ops[0].start(), content="0")
  inspect(ops[1].start(), content="2")
}
```

**Step 2: Run to verify failure**

Expected: compile error.

**Step 3: Implement**

```moonbit
///|
/// First direct token child matching `kind`, with its absolute offset.
pub fn SyntaxNode::find_token(
  self : SyntaxNode,
  kind : RawKind,
) -> SyntaxToken? {
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        if tok.kind == kind {
          return Some(SyntaxToken::new(tok, offset))
        }
        offset = offset + tok.text_len()
      }
      CstElement::Node(child) => offset = offset + child.text_len
    }
  }
  None
}

///|
/// All direct token children matching `kind`, in source order.
pub fn SyntaxNode::tokens_of_kind(
  self : SyntaxNode,
  kind : RawKind,
) -> Array[SyntaxToken] {
  let result : Array[SyntaxToken] = []
  let mut offset = self.offset
  for elem in self.cst.children {
    match elem {
      CstElement::Token(tok) => {
        if tok.kind == kind {
          result.push(SyntaxToken::new(tok, offset))
        }
        offset = offset + tok.text_len()
      }
      CstElement::Node(child) => offset = offset + child.text_len
    }
  }
  result
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: PASS.

**Step 5: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "feat(seam): add SyntaxNode::find_token and tokens_of_kind"
```

---

### Task 5: Add `tight_span()`

Replaces the `tight_span(CstNode, offset)` free function in `cst_convert.mbt`. Skips leading/trailing trivia tokens (e.g. whitespace) when computing the tight byte range. Only tokens can be trivia — interior nodes always contribute.

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`

**Step 1: Write the failing tests**

```moonbit
///|
test "SyntaxNode::tight_span no trivia" {
  let t1 = CstToken::new(RawKind(9), "ab")
  let t2 = CstToken::new(RawKind(9), "cd")
  let root = CstNode::new(
    RawKind(22),
    [CstElement::Token(t1), CstElement::Token(t2)],
  )
  let sn = SyntaxNode::from_cst(root)
  let (s, e) = sn.tight_span()
  inspect(s, content="0")
  inspect(e, content="4")
}

///|
test "SyntaxNode::tight_span skips leading and trailing trivia" {
  let ws1 = CstToken::new(RawKind(0), " ")   // trivia kind = RawKind(0)
  let ident = CstToken::new(RawKind(9), "x")
  let ws2 = CstToken::new(RawKind(0), "  ")
  let root = CstNode::new(
    RawKind(22),
    [
      CstElement::Token(ws1),
      CstElement::Token(ident),
      CstElement::Token(ws2),
    ],
  )
  let sn = SyntaxNode::from_cst(root)
  let (s, e) = sn.tight_span(trivia_kind=Some(RawKind(0)))
  inspect(s, content="1")
  inspect(e, content="3")
}
```

**Step 2: Run to verify failure**

Expected: compile error.

**Step 3: Implement**

```moonbit
///|
/// Tight byte span of this node, skipping leading and trailing trivia tokens.
///
/// Pass `trivia_kind` to identify whitespace/comment tokens to skip.
/// Interior `CstNode` children are never treated as trivia.
pub fn SyntaxNode::tight_span(
  self : SyntaxNode,
  trivia_kind~ : RawKind? = None,
) -> (Int, Int) {
  let mut pos = self.offset
  let mut tight_start = self.offset
  let mut tight_end = self.end()
  let mut found_start = false
  for elem in self.cst.children {
    let len = match elem {
      CstElement::Token(t) => t.text_len()
      CstElement::Node(n) => n.text_len
    }
    let contributes = match (elem, trivia_kind) {
      (CstElement::Token(t), Some(tk)) => t.kind != tk
      (CstElement::Token(_), None) => true
      (CstElement::Node(_), _) => true
    }
    if contributes {
      if not(found_start) {
        tight_start = pos
        found_start = true
      }
      tight_end = pos + len
    }
    pos = pos + len
  }
  (tight_start, tight_end)
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: PASS.

**Step 5: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "feat(seam): add SyntaxNode::tight_span with optional trivia filtering"
```

---

### Task 6: Add `find_at()`

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`

**Step 1: Write the failing tests**

```moonbit
///|
test "SyntaxNode::find_at returns self when no child covers offset" {
  let cst = CstNode::new(RawKind(22), [])
  let sn = SyntaxNode::from_cst(cst)
  let found = sn.find_at(0)
  inspect(found.kind() == RawKind(22), content="true")
}

///|
test "SyntaxNode::find_at drills into deepest child" {
  // Build: root[0,5) → child[0,3) → grandchild[0,2)
  let leaf_tok = CstToken::new(RawKind(9), "ab")
  let grandchild = CstNode::new(RawKind(21), [CstElement::Token(leaf_tok)])
  let child_tok = CstToken::new(RawKind(10), "c")
  let child = CstNode::new(
    RawKind(20),
    [CstElement::Node(grandchild), CstElement::Token(child_tok)],
  )
  let root_tok = CstToken::new(RawKind(11), "de")
  let root = CstNode::new(
    RawKind(22),
    [CstElement::Node(child), CstElement::Token(root_tok)],
  )
  let sn = SyntaxNode::from_cst(root)
  // offset 1 is inside grandchild [0,2)
  inspect(sn.find_at(1).kind() == RawKind(21), content="true")
  // offset 2 is inside child [0,3), past grandchild [0,2)
  inspect(sn.find_at(2).kind() == RawKind(20), content="true")
  // offset 4 is inside root only (past child [0,3))
  inspect(sn.find_at(4).kind() == RawKind(22), content="true")
}
```

**Step 2: Run to verify failure**

Expected: compile error.

**Step 3: Implement**

```moonbit
///|
/// Deepest descendant whose span contains `offset`.
/// Falls back to `self` if no child's span covers the offset.
pub fn SyntaxNode::find_at(self : SyntaxNode, offset : Int) -> SyntaxNode {
  for child in self.children() {
    if child.start() <= offset && offset < child.end() {
      return child.find_at(offset)
    }
  }
  self
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: PASS.

**Step 5: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "feat(seam): add SyntaxNode::find_at deepest-node query"
```

---

### Task 7: Add `Show` and `Debug` for `SyntaxNode`

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`

**Step 1: Write the failing tests**

```moonbit
///|
test "SyntaxNode Show" {
  let tok = CstToken::new(RawKind(9), "hello")
  let cst = CstNode::new(RawKind(20), [CstElement::Token(tok)])
  let sn = SyntaxNode::from_cst(cst)
  inspect(sn, content="SyntaxNode@[0,5)")
}

///|
test "SyntaxNode Debug" {
  let cst = CstNode::new(RawKind(20), [])
  let sn = SyntaxNode::from_cst(cst)
  inspect(
    sn.debug_string(),
    content="SyntaxNode { kind: RawKind(20), offset: 0, text_len: 0 }",
  )
}
```

**Step 2: Run to verify failure**

Expected: FAIL — no `Show` or `debug_string` on `SyntaxNode`.

**Step 3: Implement** — add to `seam/syntax_node.mbt` after the existing `SyntaxNode` methods:

```moonbit
///|
/// Show: compact form — "SyntaxNode@[start,end)"
pub impl Show for SyntaxNode with output(self, logger) {
  logger.write_string("SyntaxNode@[")
  logger.write_string(self.start().to_string())
  logger.write_string(",")
  logger.write_string(self.end().to_string())
  logger.write_string(")")
}

///|
/// Debug: structural form — "SyntaxNode { kind: ..., offset: ..., text_len: ... }"
pub impl Debug for SyntaxNode with debug_string(self) {
  "SyntaxNode { kind: " +
  self.cst.kind.to_string() +
  ", offset: " +
  self.offset.to_string() +
  ", text_len: " +
  self.cst.text_len.to_string() +
  " }"
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: PASS.

**Step 5: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "feat(seam): add Show and Debug impls for SyntaxNode"
```

---

### Task 8: Update interfaces and format

**Files:**
- Modify: `seam/pkg.generated.mbti` (auto-generated — do not edit manually)

**Step 1: Update `.mbti` and format**

```bash
cd /path/to/parser/seam && moon info && moon fmt
```

**Step 2: Review the diff**

```bash
git diff seam/pkg.generated.mbti
```

Verify the new public API entries are present:
- `SyntaxToken` struct and its methods
- `SyntaxElement` enum
- `SyntaxNode::all_children`, `tokens`, `find_token`, `tokens_of_kind`, `tight_span`, `find_at`
- `impl Show for SyntaxNode`, `impl Debug for SyntaxNode`
- `impl Show for SyntaxToken`, `impl Debug for SyntaxToken`
- `Debug` trait

**Step 3: Run full test suite one final time**

```bash
cd /path/to/parser/seam && moon test
```
Expected: all tests PASS, zero failures.

**Step 4: Commit**

```bash
git add seam/pkg.generated.mbti seam/syntax_node.mbt seam/syntax_node_wbtest.mbt
git commit -m "chore(seam): update interfaces after SyntaxNode extension (Phase 1)"
```
