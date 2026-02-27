# NodeInterner Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `NodeInterner` to `seam/` to deduplicate `CstNode` objects by structural identity, then wire it through the parser and `IncrementalParser`.

**Architecture:** Standalone `NodeInterner` struct parallel to `Interner`. `build_tree_fully_interned` in `seam/event.mbt` interns both tokens and nodes. `select_build_tree` in `cst_parser.mbt` is extended to accept an optional `NodeInterner`. `IncrementalParser` owns a `node_interner` field alongside `interner`, and `interner_clear()` clears both.

**Tech Stack:** MoonBit, `@hashmap.HashMap`, `seam` package (git submodule at `seam/`), `src/parser`, `src/incremental`.

---

## Background: two-submodule commit pattern

`seam/` is a git submodule inside `parser/`. Any changes to files under `seam/` require **two commits**:

1. Commit inside `seam/` itself:
   ```bash
   cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
   git add <files>
   git commit -m "..."
   ```
2. Update the submodule pointer from `parser/`:
   ```bash
   cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
   git add seam
   git commit -m "chore: update seam submodule pointer (...)"
   ```

Always run `moon test` from the `parser/` root (not just `seam/`) to catch cross-package issues.

---

## Task 1: NodeInterner struct and unit tests

**Files:**
- Create: `seam/node_interner.mbt`
- Create: `seam/node_interner_wbtest.mbt`

### Step 1: Write the failing tests

Create `seam/node_interner_wbtest.mbt`:

```moonbit
///|
test "NodeInterner: intern_node returns structurally equal node" {
  let ni = NodeInterner::new()
  let node = CstNode::new(RawKind(1), [])
  let result = ni.intern_node(node)
  inspect(result == node, content="true")
}

///|
test "NodeInterner: second call for equal structure does not grow size" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  let _ = ni.intern_node(CstNode::new(RawKind(1), [])) // structurally equal
  inspect(ni.size(), content="1")
}

///|
test "NodeInterner: distinct structures get distinct entries" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  let _ = ni.intern_node(CstNode::new(RawKind(2), []))
  inspect(ni.size(), content="2")
}

///|
test "NodeInterner: clear resets size to zero" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  inspect(ni.size(), content="1")
  ni.clear()
  inspect(ni.size(), content="0")
}

///|
test "NodeInterner: intern works correctly after clear" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  ni.clear()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  inspect(ni.size(), content="1")
}

///|
test "NodeInterner: parent with interned children deduplicates" {
  let ni = NodeInterner::new()
  let child = ni.intern_node(CstNode::new(RawKind(1), []))
  let p1 = CstNode::new(RawKind(2), [Node(child)])
  let p2 = CstNode::new(RawKind(2), [Node(child)])
  let _ = ni.intern_node(p1)
  let _ = ni.intern_node(p2)
  inspect(ni.size(), content="2") // child + parent, no duplicate parent
}
```

### Step 2: Run to verify failure

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
moon test
```

Expected: FAIL — `NodeInterner` type not found.

### Step 3: Implement NodeInterner

Create `seam/node_interner.mbt`:

```moonbit
///|
/// Session-scoped node intern table.
///
/// Deduplicates CstNode objects by structural identity: every call to
/// intern_node with a structurally equal CstNode returns the first-seen
/// reference. Lookup uses CstNode::Hash (the cached structural hash, O(1))
/// as a fast path, then CstNode::Eq for collision resolution.
///
/// Lifetime: own one NodeInterner per parse session (e.g. per IncrementalParser).
/// The GC collects the NodeInterner and all its nodes when the owner is dropped.
/// Not thread-safe.
pub struct NodeInterner {
  priv nodes : @hashmap.HashMap[CstNode, CstNode]
}

///|
/// Create a new empty NodeInterner.
pub fn NodeInterner::new() -> NodeInterner {
  { nodes: @hashmap.HashMap::new() }
}

///|
/// Return the canonical CstNode structurally equal to `node`.
/// First call for a given structure: stores and returns `node`.
/// Subsequent calls with an equal structure: returns the first-seen reference.
pub fn NodeInterner::intern_node(self : NodeInterner, node : CstNode) -> CstNode {
  match self.nodes.get(node) {
    Some(cached) => cached
    None => {
      self.nodes.set(node, node)
      node
    }
  }
}

///|
/// Number of distinct CstNode structures currently interned.
pub fn NodeInterner::size(self : NodeInterner) -> Int {
  self.nodes.size()
}

///|
/// Clear all interned nodes. The NodeInterner can be reused after this call,
/// e.g. when starting a new document in a long-lived language server session.
pub fn NodeInterner::clear(self : NodeInterner) -> Unit {
  self.nodes.clear()
}
```

### Step 4: Run to verify pass

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
moon test
```

Expected: all tests pass including the 6 new NodeInterner tests.

Also run from parser root:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon test
```

Expected: `Total tests: NNN, passed: NNN, failed: 0`

### Step 5: Commit (two commits)

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
git add node_interner.mbt node_interner_wbtest.mbt
git commit -m "feat(seam): add NodeInterner for CstNode structural deduplication"
```

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git add seam
git commit -m "chore: update seam submodule pointer (add NodeInterner)"
```

---

## Task 2: build_tree_fully_interned

**Files:**
- Modify: `seam/event.mbt`

### Step 1: Write the failing test

Add to `seam/event_wbtest.mbt`:

```moonbit
///|
test "build_tree_fully_interned: identical subtrees share canonical reference" {
  let interner = Interner::new()
  let ni = NodeInterner::new()
  // Two identical trees built from the same events
  let events : Array[ParseEvent] = [
    Token(RawKind(1), "x"),
  ]
  let ws = RawKind(99)
  let root_kind = RawKind(0)
  let t1 = build_tree_fully_interned(events, root_kind, interner, ni, trivia_kind=Some(ws))
  let t2 = build_tree_fully_interned(events, root_kind, interner, ni, trivia_kind=Some(ws))
  inspect(t1 == t2, content="true")
  inspect(ni.size() <= 2, content="true") // root + child, no duplication
}
```

### Step 2: Run to verify failure

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
moon test
```

Expected: FAIL — `build_tree_fully_interned` not found.

### Step 3: Implement

Add to `seam/event.mbt` after the existing `build_tree_interned` function:

```moonbit
///|
/// Build an interned CST from this buffer's events, interning both tokens
/// and interior nodes.
pub fn EventBuffer::build_tree_fully_interned(
  self : EventBuffer,
  root_kind : RawKind,
  interner : Interner,
  node_interner : NodeInterner,
  trivia_kind? : RawKind? = None,
) -> CstNode {
  build_tree_fully_interned(
    self.events, root_kind, interner, node_interner, trivia_kind~,
  )
}

///|
/// Build a CST from a flat event stream, interning tokens via `interner` and
/// interior nodes via `node_interner`. Identical subtrees share a single
/// canonical CstNode reference in memory.
///
/// Construction is bottom-up: children are interned before their parent, so
/// the parent's equality check terminates at hash match without deep recursion.
///
/// `trivia_kind`: forwarded to every `CstNode::new` call; leaf tokens with
/// this kind are excluded from each node's `token_count`.
pub fn build_tree_fully_interned(
  events : Array[ParseEvent],
  root_kind : RawKind,
  interner : Interner,
  node_interner : NodeInterner,
  trivia_kind? : RawKind? = None,
) -> CstNode {
  let stack : Array[Array[CstElement]] = [[]]
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
              "build_tree_fully_interned: unbalanced FinishNode — no matching StartNode",
            )
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None =>
            abort(
              "build_tree_fully_interned: kind stack underflow on FinishNode",
            )
        }
        let node = node_interner.intern_node(
          CstNode::new(kind, children, trivia_kind~),
        )
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort(
              "build_tree_fully_interned: parent stack empty when attaching node",
            )
        }
      }
      Token(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None =>
            abort("build_tree_fully_interned: stack empty when adding token")
        }
      }
      Tombstone => ()
    }
  }
  if stack.length() != 1 {
    abort(
      "build_tree_fully_interned: unbalanced StartNode — missing FinishNode(s), stack=" +
      stack.length().to_string(),
    )
  }
  node_interner.intern_node(CstNode::new(root_kind, stack[0], trivia_kind~))
}
```

### Step 4: Run to verify pass

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
moon test
```

Then from parser root:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon test
```

Expected: all tests pass.

### Step 5: Commit (two commits)

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
git add event.mbt event_wbtest.mbt
git commit -m "feat(seam): add build_tree_fully_interned for node deduplication"
```

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git add seam
git commit -m "chore: update seam submodule pointer (build_tree_fully_interned)"
```

---

## Task 3: Wire node_interner through cst_parser.mbt

**Files:**
- Modify: `src/parser/cst_parser.mbt`

The key function is `select_build_tree` — it decides which `build_tree_*` variant to call. Extend it to accept `node_interner?`, then thread that through `run_parse`, `run_parse_incremental`, `parse_cst_recover`, and `parse_cst_recover_with_tokens`.

### Step 1: No failing test needed for this task

The existing tests cover correct parse output. This task adds an optional parameter with `None` as default — existing callers are unchanged.

Run the existing tests first to confirm baseline:

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon test
```

Expected: all pass.

### Step 2: Extend select_build_tree

In `src/parser/cst_parser.mbt`, find `select_build_tree` (currently ~line 71). Replace it:

```moonbit
///|
fn select_build_tree(
  buf : @seam.EventBuffer,
  interner : @seam.Interner?,
  node_interner : @seam.NodeInterner?,
) -> @seam.CstNode {
  let ws = raw(@syntax.WhitespaceToken)
  match (interner, node_interner) {
    (Some(i), Some(ni)) =>
      buf.build_tree_fully_interned(
        raw(@syntax.SourceFile), i, ni, trivia_kind=Some(ws),
      )
    (Some(i), None) =>
      buf.build_tree_interned(raw(@syntax.SourceFile), i, trivia_kind=Some(ws))
    _ => buf.build_tree(raw(@syntax.SourceFile), trivia_kind=Some(ws))
  }
}
```

### Step 3: Extend run_parse

Find `run_parse` (currently ~line 101). Add `node_interner` parameter and update the `select_build_tree` call:

```moonbit
///|
fn run_parse(
  tokens : Array[@token.TokenInfo],
  source : String,
  interner : @seam.Interner?,
  node_interner : @seam.NodeInterner?,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) {
  let ctx = @core.ParserContext::new_indexed(
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    source,
    lambda_spec,
  )
  parse_lambda_root(ctx)
  ctx.flush_trivia()
  if ctx.open_nodes != 0 {
    abort(
      "run_parse: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
  (select_build_tree(ctx.events, interner, node_interner), ctx.errors)
}
```

### Step 4: Extend run_parse_incremental

Find `run_parse_incremental` (currently ~line 33). Add `node_interner` parameter:

```moonbit
///|
fn run_parse_incremental(
  tokens : Array[@token.TokenInfo],
  source : String,
  interner : @seam.Interner?,
  node_interner : @seam.NodeInterner?,
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
  prev_diagnostics : Array[@core.Diagnostic[@token.Token]]?,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  let ctx = @core.ParserContext::new_indexed(
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    source,
    lambda_spec,
  )
  match cursor {
    Some(c) => {
      ctx.set_reuse_cursor(c)
      match prev_diagnostics {
        Some(prev) => ctx.set_reuse_diagnostics(prev)
        None => ()
      }
    }
    None => ()
  }
  parse_lambda_root(ctx)
  ctx.flush_trivia()
  if ctx.open_nodes != 0 {
    abort(
      "run_parse_incremental: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
  (
    select_build_tree(ctx.events, interner, node_interner),
    ctx.errors,
    ctx.reuse_count,
  )
}
```

### Step 5: Extend public API functions

Update `parse_cst_recover`:

```moonbit
///|
pub fn parse_cst_recover(
  source : String,
  interner? : @seam.Interner? = None,
  node_interner? : @seam.NodeInterner? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @lexer.TokenizationError {
  let tokens = @lexer.tokenize(source)
  run_parse(tokens, source, interner, node_interner)
}
```

Update `parse_cst_recover_with_tokens`:

```moonbit
///|
pub fn parse_cst_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
  interner? : @seam.Interner? = None,
  node_interner? : @seam.NodeInterner? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  run_parse_incremental(
    tokens, source, interner, node_interner, cursor, prev_diagnostics,
  )
}
```

### Step 6: Run to verify pass

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon test
```

Expected: all tests pass (new parameters default to `None` so existing callers are unaffected).

### Step 7: Commit

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git add src/parser/cst_parser.mbt
git commit -m "feat(parser): thread node_interner? through cst_parser build path"
```

---

## Task 4: Wire node_interner into IncrementalParser

**Files:**
- Modify: `src/incremental/incremental_parser.mbt`
- Create: `src/incremental/node_interner_integration_test.mbt`

### Step 1: Write the failing integration tests

Create `src/incremental/node_interner_integration_test.mbt`:

```moonbit
// Integration tests for NodeInterner wiring in IncrementalParser

///|
test "NodeInterner: size is positive after non-empty parse" {
  let parser = IncrementalParser::new("λx.x")
  let _ = parser.parse()
  inspect(parser.node_interner_size() > 0, content="true")
}

///|
test "NodeInterner: interner_clear resets node_interner_size to zero" {
  let parser = IncrementalParser::new("λx.x")
  let _ = parser.parse()
  parser.interner_clear()
  inspect(parser.node_interner_size(), content="0")
}

///|
test "NodeInterner: interner_clear resets both token and node interners" {
  let parser = IncrementalParser::new("λf.λx.f (f x)")
  let _ = parser.parse()
  parser.interner_clear()
  inspect(parser.interner_size(), content="0")
  inspect(parser.node_interner_size(), content="0")
}

///|
test "NodeInterner: size does not grow on identical re-parse" {
  let parser = IncrementalParser::new("λx.x")
  let _ = parser.parse()
  let size_after_initial = parser.node_interner_size()

  // Zero-length edit: source is unchanged
  let edit = @edit.Edit::insert(4, 0)
  let _ = parser.edit(edit, "λx.x")
  let size_after_noop = parser.node_interner_size()

  inspect(size_after_noop <= size_after_initial, content="true")
}

///|
test "NodeInterner: parse result unchanged after adding node_interner" {
  let parser = IncrementalParser::new("λf.λx.f (f x)")
  let tree = parser.parse()
  let full_tree = @parse.parse_tree("λf.λx.f (f x)")
  inspect(@ast.print_ast_node(tree), content=@ast.print_ast_node(full_tree))
}
```

### Step 2: Run to verify failure

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon test
```

Expected: FAIL — `node_interner_size` method not found.

### Step 3: Update IncrementalParser struct and new()

In `src/incremental/incremental_parser.mbt`:

**Update the doc comment** — replace the paragraph starting "The internal `Interner`..." with:

```moonbit
/// **Lifetime:** `IncrementalParser` is designed to be created once per document
/// and kept alive for the document's editing session. The internal `Interner`
/// accumulates one entry per distinct `(kind, text)` token pair ever seen; this
/// is bounded by the document's token vocabulary, not by edit count. The internal
/// `NodeInterner` accumulates one entry per distinct structural subtree ever seen;
/// this is bounded by the document's subtree vocabulary, not by edit count.
///
/// For scenarios where the same `IncrementalParser` instance is reused across
/// unrelated documents (e.g., a long-lived LSP process that re-uses parser
/// objects), call `interner_clear()` between documents to release stale entries.
```

**Update the struct** — add field after `interner`:

```moonbit
pub struct IncrementalParser {
  mut source : String
  mut tree : @ast.AstNode?
  mut syntax_tree : @seam.SyntaxNode?
  mut token_buffer : @lexer.TokenBuffer?
  mut last_reuse_count : Int
  mut last_diagnostics : Array[@core.Diagnostic[@token.Token]]
  priv interner : @seam.Interner
  priv node_interner : @seam.NodeInterner  // session-scoped node intern table
}
```

**Update `::new()`**:

```moonbit
pub fn IncrementalParser::new(source : String) -> IncrementalParser {
  {
    source,
    tree: None,
    syntax_tree: None,
    token_buffer: None,
    last_reuse_count: 0,
    last_diagnostics: [],
    interner: @seam.Interner::new(),
    node_interner: @seam.NodeInterner::new(),
  }
}
```

### Step 4: Add node_interner_size() and update interner_clear()

Add after `interner_size()`:

```moonbit
///|
/// Number of distinct structural subtrees currently interned. For diagnostics and tests.
pub fn IncrementalParser::node_interner_size(self : IncrementalParser) -> Int {
  self.node_interner.size()
}
```

Update `interner_clear()`:

```moonbit
///|
/// Clear both intern tables, releasing all cached token and node entries.
///
/// Only needed when reusing the same `IncrementalParser` across unrelated
/// documents. For normal single-document use this is never required, since the
/// parser is created once per document and the intern tables stay bounded by
/// that document's vocabulary.
pub fn IncrementalParser::interner_clear(self : IncrementalParser) -> Unit {
  self.interner.clear()
  self.node_interner.clear()
}
```

### Step 5: Update parse() call site

In `parse()`, update the `parse_cst_recover` call:

```moonbit
let (cst, diagnostics) = @parse.parse_cst_recover(
  self.source,
  interner=Some(self.interner),
  node_interner=Some(self.node_interner),
)
```

### Step 6: Update incremental_reparse() call site

In `incremental_reparse()`, update the `parse_cst_recover_with_tokens` call:

```moonbit
let (new_cst, diagnostics, reuse_count) = @parse.parse_cst_recover_with_tokens(
  source,
  tokens,
  cursor,
  prev_diagnostics=Some(self.last_diagnostics),
  interner=Some(self.interner),
  node_interner=Some(self.node_interner),
)
```

### Step 7: Run to verify pass

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon test
```

Expected: all tests pass including the 5 new integration tests.

### Step 8: Commit

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git add src/incremental/incremental_parser.mbt \
        src/incremental/node_interner_integration_test.mbt
git commit -m "feat(incremental): wire NodeInterner into IncrementalParser"
```

---

## Task 5: Update interfaces and format

**Files:**
- Modify: `seam/pkg.generated.mbti`
- Modify: `src/parser/pkg.generated.mbti`
- Modify: `src/incremental/pkg.generated.mbti`

### Step 1: Regenerate interfaces and format

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
moon info && moon fmt
```

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon info && moon fmt
```

### Step 2: Review diffs

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
git diff pkg.generated.mbti
```

Expected additions:
- `pub struct NodeInterner` with `// private fields`
- `pub fn NodeInterner::new() -> NodeInterner`
- `pub fn NodeInterner::intern_node(Self, CstNode) -> CstNode`
- `pub fn NodeInterner::size(Self) -> Int`
- `pub fn NodeInterner::clear(Self) -> Unit`
- `pub fn build_tree_fully_interned(Array[ParseEvent], RawKind, Interner, NodeInterner, trivia_kind? : RawKind?) -> CstNode`
- `pub fn EventBuffer::build_tree_fully_interned(Self, RawKind, Interner, NodeInterner, trivia_kind? : RawKind?) -> CstNode`

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git diff src/parser/pkg.generated.mbti
```

Expected additions to `parse_cst_recover` and `parse_cst_recover_with_tokens` signatures: `node_interner? : @seam.NodeInterner?` parameter.

```bash
git diff src/incremental/pkg.generated.mbti
```

Expected additions:
- `mut node_interner : @seam.NodeInterner` field on `IncrementalParser`
- `pub fn IncrementalParser::node_interner_size(Self) -> Int`

### Step 3: Run final test suite

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon test
```

Expected: all tests pass, `failed: 0`.

### Step 4: Commit (two commits)

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser/seam
git add pkg.generated.mbti
git commit -m "chore(seam): update interface after adding NodeInterner"
```

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git add seam src/parser/pkg.generated.mbti src/incremental/pkg.generated.mbti
git commit -m "chore: update interfaces after NodeInterner wiring"
```
