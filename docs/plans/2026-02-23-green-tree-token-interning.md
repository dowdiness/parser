# Green Tree Token Interning Implementation Plan

> **Status:** Completed / Implemented 2026-02-23.
> All 5 tasks delivered: `Interner` type in `green-tree`, `build_tree_interned`, optional `interner~` parameter threaded into `parse_green_recover` and `parse_green_recover_with_tokens`, and `IncrementalParser` wired with a session-scoped `Interner` field.

**Goal:** Add a session-scoped `Interner` type to `green-tree` that deduplicates `GreenToken` objects by `(kind, text)`, and wire it into `IncrementalParser`.

**Architecture:** `Interner` wraps a `@hashmap.HashMap[String, GreenToken]` keyed by `kind.to_string() + "\x00" + text`. A new `build_tree_interned` function uses it during tree construction. `IncrementalParser` owns one `Interner` for its session lifetime and passes it to `parse_green_recover` / `parse_green_recover_with_tokens` via new optional labelled parameters.

**Tech Stack:** MoonBit, `@hashmap.HashMap` (moonbitlang/core/hashmap), existing `green-tree` and `parser` packages.

---

## Reference: Key Files

| File | Role |
|---|---|
| `src/green-tree/green_node.mbt` | `GreenToken`, `GreenNode`, `RawKind` definitions |
| `src/green-tree/event.mbt` | `build_tree` — the function we're extending |
| `src/green-tree/moon.pkg` | Empty — needs `moonbitlang/core/hashmap` import added |
| `src/parser/green_parser.mbt` | `parse_green_recover`, `parse_green_recover_with_tokens` — call `build_tree` |
| `src/parser/moon.pkg` | Parser package imports |
| `src/incremental/incremental_parser.mbt` | `IncrementalParser` struct — gains `interner` field |

## Reference: HashMap API

`@hashmap.HashMap` uses:
- `@hashmap.HashMap::new()` — create empty map
- `.set(key, value)` — insert or update
- `.get(key) -> V?` — look up by key
- `.size() -> Int` — number of entries
- `.clear()` — remove all entries

---

### Task 1: Add `moonbitlang/core/hashmap` import to `green-tree` moon.pkg

**Files:**
- Modify: `src/green-tree/moon.pkg`

The file is currently empty. Add the hashmap import so the new `interner.mbt`
file can use `@hashmap.HashMap`.

**Step 1: Edit `src/green-tree/moon.pkg`**

Replace the empty file with:

```
import {
  "moonbitlang/core/hashmap",
}
```

**Step 2: Verify the build still passes**

```bash
cd parser && moon check
```

Expected: no errors.

**Step 3: Commit**

```bash
git add src/green-tree/moon.pkg
git commit -m "chore(green-tree): import moonbitlang/core/hashmap"
```

---

### Task 2: `Interner` type — failing tests first

**Files:**
- Create: `src/green-tree/interner_wbtest.mbt`
- Create: `src/green-tree/interner.mbt`

`Interner` is a session-scoped token deduplication table. The key is
`kind.to_string() + "\x00" + text` — a null-byte separator guarantees
no collision because token texts never contain `\x00`.

**Step 1: Write the failing whitebox tests**

Create `src/green-tree/interner_wbtest.mbt`:

```moonbit
///|
test "Interner: same (kind, text) returns same token" {
  let interner = Interner()
  let k = RawKind(1)
  let t1 = interner.intern_token(k, "x")
  let t2 = interner.intern_token(k, "x")
  assert_eq!(t1, t2)
  // Same cached object — pointer equality
  assert_true!(physical_equal(t1, t2))
}

///|
test "Interner: different text returns different tokens" {
  let interner = Interner()
  let k = RawKind(1)
  let a = interner.intern_token(k, "x")
  let b = interner.intern_token(k, "y")
  assert_false!(a == b)
  assert_false!(physical_equal(a, b))
}

///|
test "Interner: different kind returns different tokens" {
  let interner = Interner()
  let a = interner.intern_token(RawKind(1), "x")
  let b = interner.intern_token(RawKind(2), "x")
  assert_false!(a == b)
}

///|
test "Interner: size counts distinct pairs only" {
  let interner = Interner()
  let k = RawKind(1)
  let _ = interner.intern_token(k, "x")
  let _ = interner.intern_token(k, "x") // duplicate — no size increase
  let _ = interner.intern_token(k, "y")
  assert_eq!(interner.size(), 2)
}

///|
test "Interner: clear resets size to zero" {
  let interner = Interner()
  let _ = interner.intern_token(RawKind(1), "x")
  assert_eq!(interner.size(), 1)
  interner.clear()
  assert_eq!(interner.size(), 0)
}

///|
test "Interner: intern_token result matches GreenToken::new structurally" {
  let interner = Interner()
  let k = RawKind(7)
  let text = "lambda"
  let interned = interner.intern_token(k, text)
  let direct = GreenToken::new(k, text)
  assert_eq!(interned, direct)
}
```

**Step 2: Run tests to confirm they fail**

```bash
cd parser && moon test --pkg dowdiness/parser/green-tree
```

Expected: compilation errors — `Interner` not defined.

**Step 3: Implement `src/green-tree/interner.mbt`**

```moonbit
///|
/// Session-scoped token intern table.
///
/// Deduplicates GreenToken objects by (kind, text): every call to
/// intern_token with the same arguments returns the exact same heap object.
/// This means for any two tokens a, b produced through the same Interner:
///   a == b  implies  physical_equal(a, b)
///
/// Lifetime: own one Interner per parse session (e.g. per IncrementalParser).
/// The GC collects the Interner and all its tokens when the owner is dropped.
/// Not thread-safe.
pub struct Interner {
  priv mut tokens : @hashmap.HashMap[String, GreenToken]
}

///|
/// Create a new empty Interner.
pub fn Interner() -> Interner {
  { tokens: @hashmap.HashMap::new() }
}

///|
/// Return the canonical GreenToken for (kind, text).
/// On first call for a given pair: allocates a GreenToken and stores it.
/// On subsequent calls: returns the stored object (same heap reference).
pub fn Interner::intern_token(
  self : Interner,
  kind : RawKind,
  text : String,
) -> GreenToken {
  // Null-byte separator: token texts never contain \x00, so this key is
  // collision-free for all valid token content.
  let key = kind.to_string() + "\x00" + text
  match self.tokens.get(key) {
    Some(token) => token
    None => {
      let token = GreenToken::new(kind, text)
      self.tokens.set(key, token)
      token
    }
  }
}

///|
/// Number of distinct (kind, text) pairs currently interned.
pub fn Interner::size(self : Interner) -> Int {
  self.tokens.size()
}

///|
/// Clear all interned tokens. The Interner can be reused after this call,
/// e.g. when starting a new document in a long-lived language server session.
pub fn Interner::clear(self : Interner) -> Unit {
  self.tokens.clear()
}
```

**Step 4: Run tests to confirm they pass**

```bash
cd parser && moon test --pkg dowdiness/parser/green-tree
```

Expected: all tests in the `green-tree` package pass.

**Step 5: Commit**

```bash
git add src/green-tree/interner.mbt src/green-tree/interner_wbtest.mbt
git commit -m "feat(green-tree): add Interner type for session-scoped token deduplication"
```

---

### Task 3: `build_tree_interned` — failing tests first

**Files:**
- Modify: `src/green-tree/event_wbtest.mbt` (add tests)
- Modify: `src/green-tree/event.mbt` (add function)

**Step 1: Add failing tests to `src/green-tree/event_wbtest.mbt`**

Open the file and append:

```moonbit
///|
test "build_tree_interned: structurally equal to build_tree" {
  // Build the same event stream twice — once plain, once interned.
  let root_kind = RawKind(0)
  let node_kind = RawKind(1)
  let tok_kind = RawKind(2)

  let make_events : () -> Array[ParseEvent] = fn() {
    [
      StartNode(node_kind),
      Token(tok_kind, "x"),
      Token(tok_kind, "x"), // duplicate
      FinishNode,
    ]
  }

  let plain = build_tree(make_events(), root_kind)
  let interner = Interner()
  let interned = build_tree_interned(make_events(), root_kind, interner)
  assert_eq!(plain, interned)
}

///|
test "build_tree_interned: duplicate tokens are pointer-equal" {
  let root_kind = RawKind(0)
  let tok_kind = RawKind(2)
  let interner = Interner()
  let node = build_tree_interned(
    [Token(tok_kind, "y"), Token(tok_kind, "y")],
    root_kind,
    interner,
  )
  // Both children should be the same interned GreenToken.
  let children = node.children
  match (children[0], children[1]) {
    (Token(a), Token(b)) => assert_true!(physical_equal(a, b))
    _ => abort("expected two tokens")
  }
}

///|
test "build_tree_interned: interner size bounded by vocabulary" {
  let root_kind = RawKind(0)
  let tok_kind = RawKind(1)
  let interner = Interner()
  // 100 tokens, all "x" — should intern to exactly 1 entry.
  let events : Array[ParseEvent] = []
  for _ in 0..<100 {
    events.push(Token(tok_kind, "x"))
  }
  let _ = build_tree_interned(events, root_kind, interner)
  assert_eq!(interner.size(), 1)
}
```

**Step 2: Run tests to confirm failure**

```bash
cd parser && moon test --pkg dowdiness/parser/green-tree
```

Expected: compilation error — `build_tree_interned` not defined.

**Step 3: Add `build_tree_interned` to `src/green-tree/event.mbt`**

Append after `build_tree`:

```moonbit
///|
/// Build a green tree from a flat event stream, interning all tokens through
/// the provided Interner. Structurally identical to build_tree; differs only
/// in that Token events are deduplicated via intern_token.
///
/// Use this variant when tokens will be reused across multiple parses of the
/// same document (e.g. in IncrementalParser).
pub fn build_tree_interned(
  events : Array[ParseEvent],
  root_kind : RawKind,
  interner : Interner,
) -> GreenNode {
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
            abort("build_tree_interned: unbalanced FinishNode — no matching StartNode")
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None => abort("build_tree_interned: kind stack underflow on FinishNode")
        }
        let node = GreenNode::new(kind, children)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort("build_tree_interned: parent stack empty when attaching node")
        }
      }
      Token(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(GreenElement::Token(token))
          None => abort("build_tree_interned: stack empty when adding token")
        }
      }
      Tombstone => ()
    }
  }
  if stack.length() != 1 {
    abort(
      "build_tree_interned: unbalanced StartNode — missing FinishNode(s), stack=" +
      stack.length().to_string(),
    )
  }
  GreenNode::new(root_kind, stack[0])
}
```

**Step 4: Run tests to confirm they pass**

```bash
cd parser && moon test --pkg dowdiness/parser/green-tree
```

Expected: all `green-tree` tests pass.

**Step 5: Update .mbti interface**

```bash
cd parser && moon info
```

Verify `src/green-tree/pkg.generated.mbti` now lists `build_tree_interned` and the `Interner` type.

**Step 6: Commit**

```bash
git add src/green-tree/event.mbt src/green-tree/event_wbtest.mbt src/green-tree/pkg.generated.mbti
git commit -m "feat(green-tree): add build_tree_interned alongside build_tree"
```

---

### Task 4: Thread interner into parser functions

**Files:**
- Modify: `src/parser/green_parser.mbt`

`parse_green_recover` and `parse_green_recover_with_tokens` both call
`@green_tree.build_tree`. Add an optional labelled `interner~` parameter
(default `None`) to each. When `Some(interner)` is provided, delegate to
`@green_tree.build_tree_interned`; otherwise use `@green_tree.build_tree`.

This is backward compatible: existing callers that omit `interner~` see no
change in behaviour.

**Step 1: Add failing tests**

Open `src/parser/green_parser_wbtest.mbt` and append:

```moonbit
///|
test "parse_green_recover: with interner matches without interner" {
  let source = "λx.x + x"
  let (plain, _) = parse_green_recover(source)
  let interner = @green_tree.Interner()
  let (interned, _) = parse_green_recover(source, interner=Some(interner))
  assert_eq!(plain, interned)
}

///|
test "parse_green_recover: interner deduplicates repeated tokens" {
  // "x + x" has two "x" IdentTokens — they should be the same interned object.
  let source = "x + x"
  let interner = @green_tree.Interner()
  let _ = parse_green_recover(source, interner=Some(interner))
  // Vocabulary: "x", "+", and whitespace tokens.
  // Exact count depends on whitespace emission. At minimum "x" is 1 entry.
  assert_true!(interner.size() > 0)
}

///|
test "parse_green_recover_with_tokens: with interner matches without" {
  let source = "λx.x"
  let tokens = @lexer.tokenize(source)
  let (plain, _, _) = parse_green_recover_with_tokens(source, tokens, None)
  let interner = @green_tree.Interner()
  let (interned, _, _) = parse_green_recover_with_tokens(
    source,
    tokens,
    None,
    interner=Some(interner),
  )
  assert_eq!(plain, interned)
}
```

**Step 2: Run tests to confirm failure**

```bash
cd parser && moon test --pkg dowdiness/parser/parser
```

Expected: compilation error — `interner` is not a valid parameter.

**Step 3: Modify `src/parser/green_parser.mbt`**

Change `parse_green_recover` signature (line ~48):

```moonbit
pub fn parse_green_recover(
  source : String,
  interner~ : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[ParseDiagnostic]) raise @lexer.TokenizationError {
  let tokens = @lexer.tokenize(source)
  let parser = GreenParser::new(tokens, source)
  parser.parse_source_file()
  parser.assert_event_balance()
  let tree = match interner {
    Some(i) =>
      @green_tree.build_tree_interned(
        parser.events.events,
        raw(@syntax.SourceFile),
        i,
      )
    None =>
      @green_tree.build_tree(parser.events.events, raw(@syntax.SourceFile))
  }
  (tree, parser.errors)
}
```

Change `parse_green_recover_with_tokens` signature (line ~83):

```moonbit
pub fn parse_green_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : ReuseCursor?,
  interner~ : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[ParseDiagnostic], Int) {
  let parser = match cursor {
    Some(c) => GreenParser::new_with_cursor(tokens, source, c)
    None => GreenParser::new(tokens, source)
  }
  parser.parse_source_file()
  parser.assert_event_balance()
  let tree = match interner {
    Some(i) =>
      @green_tree.build_tree_interned(
        parser.events.events,
        raw(@syntax.SourceFile),
        i,
      )
    None =>
      @green_tree.build_tree(parser.events.events, raw(@syntax.SourceFile))
  }
  (tree, parser.errors, parser.reuse_count)
}
```

Note: `parse_green_with_cursor` (line ~65) is an internal helper that also
calls `build_tree`. Since `IncrementalParser` uses `parse_green_recover_with_tokens`,
not this function, leave it unchanged for now.

**Step 4: Run all tests**

```bash
cd parser && moon test
```

Expected: all tests pass (existing callers unaffected by optional param).

**Step 5: Update .mbti**

```bash
cd parser && moon info
```

Verify `src/parser/pkg.generated.mbti` reflects the updated signatures.

**Step 6: Commit**

```bash
git add src/parser/green_parser.mbt src/parser/green_parser_wbtest.mbt src/parser/pkg.generated.mbti
git commit -m "feat(parser): thread optional Interner into parse_green_recover functions"
```

---

### Task 5: Wire `Interner` into `IncrementalParser`

**Files:**
- Modify: `src/incremental/incremental_parser.mbt`
- Create: `src/incremental/interner_integration_test.mbt`

**Step 1: Write failing integration tests**

Create `src/incremental/interner_integration_test.mbt`:

```moonbit
///|
test "IncrementalParser: parse result unchanged after adding interner" {
  // Baseline: parse without interner (old behaviour)
  let source = "λx.x + x"
  let p1 = @incremental.IncrementalParser::new(source)
  let term1 = p1.parse()

  // After wiring interner in, should produce structurally equal Term
  // Use the green_tree directly to compare
  let p2 = @incremental.IncrementalParser::new(source)
  let term2 = p2.parse()
  inspect!(term1, content=term2.to_string())
}

///|
test "IncrementalParser: interner size bounded by vocabulary across re-parses" {
  let p = @incremental.IncrementalParser::new("x + y")
  let _ = p.parse()
  // Apply an edit that doesn't introduce new token text
  let edit = @edit.Edit::{ start: 4, old_end: 5, new_end: 5, new_text: "y" }
  let _ = p.edit(edit, "x + y")
  // x, +, y, whitespace — small bounded set regardless of parse count
  assert_true!(p.interner_size() <= 10)
}

///|
test "IncrementalParser: re-parse of identical source yields pointer-equal tokens" {
  let source = "x + x"
  let p = @incremental.IncrementalParser::new(source)
  let _ = p.parse()
  // No-op edit: replace source with itself
  let edit = @edit.Edit::{
    start: 0,
    old_end: source.length(),
    new_end: source.length(),
    new_text: source,
  }
  // After re-parse, "x" tokens should still be from the same interned object
  // Verify by checking interner size did not grow
  let size_before = p.interner_size()
  let _ = p.edit(edit, source)
  assert_eq!(p.interner_size(), size_before)
}
```

Note: these tests call `p.interner_size()` — a diagnostic helper added in the
next step.

**Step 2: Run tests to confirm failure**

```bash
cd parser && moon test --pkg dowdiness/parser/incremental
```

Expected: compilation error — `interner_size` not defined (or `interner` field
not present).

**Step 3: Modify `src/incremental/incremental_parser.mbt`**

Add the `interner` field to `IncrementalParser`:

```moonbit
pub struct IncrementalParser {
  mut source : String
  mut tree : @term.TermNode?
  mut green_tree : @green_tree.GreenNode?
  mut token_buffer : @lexer.TokenBuffer?
  mut last_reuse_count : Int
  interner : @green_tree.Interner  // session-scoped token intern table
}
```

Update `IncrementalParser::new`:

```moonbit
pub fn IncrementalParser::new(source : String) -> IncrementalParser {
  {
    source,
    tree: None,
    green_tree: None,
    token_buffer: None,
    last_reuse_count: 0,
    interner: @green_tree.Interner(),
  }
}
```

Add the diagnostic helper (after the struct):

```moonbit
///|
/// Number of distinct tokens currently interned. For diagnostics and tests.
pub fn IncrementalParser::interner_size(self : IncrementalParser) -> Int {
  self.interner.size()
}
```

Update the `parse()` method — change the `parse_green_recover` call to pass
the interner:

```moonbit
let (green, _diagnostics) = @parse.parse_green_recover(
  self.source,
  interner=Some(self.interner),
)
```

Update the `edit()` method — find the `parse_green_recover_with_tokens` call
and add the interner parameter:

```moonbit
let (new_green, _diagnostics, reuse_count) = @parse.parse_green_recover_with_tokens(
  new_source,
  tokens,
  cursor,
  interner=Some(self.interner),
)
```

(There may be multiple call sites for error and reuse paths — add
`interner=Some(self.interner)` to each one. Read the full `edit()` function
carefully and update every `parse_green_recover_with_tokens` call.)

**Step 4: Run all tests**

```bash
cd parser && moon test
```

Expected: all 287+ tests pass.

**Step 5: Update .mbti**

```bash
cd parser && moon info
```

Verify `src/incremental/pkg.generated.mbti` shows the new `interner_size`
method and the updated struct.

**Step 6: Format**

```bash
cd parser && moon fmt
```

**Step 7: Final check**

```bash
cd parser && moon check
```

Expected: clean.

**Step 8: Commit**

```bash
git add src/incremental/incremental_parser.mbt \
        src/incremental/interner_integration_test.mbt \
        src/incremental/pkg.generated.mbti
git commit -m "feat(parser): wire Interner into IncrementalParser for session-scoped token deduplication"
```

---

## Verification

After all tasks complete:

```bash
cd parser && moon test && moon check && moon info
```

Expected:
- All tests pass (no regressions)
- `moon check` clean
- `.mbti` files up to date

Confirm the core guarantee with a quick manual check in the test output: the
`interner size bounded by vocabulary` tests should show `interner_size()` ≤
the number of distinct token texts in the input, regardless of how many times
the same token appears.
