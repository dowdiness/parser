# Generic Parser Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract a generic `ParserContext[T, K]` API inside the existing `parser` module so any MoonBit project can reuse the green tree, error recovery, and incremental infrastructure by defining their own token and syntax-kind types plus grammar functions.

**Architecture:** Add a new `src/core/` package inside `dowdiness/parser` that defines three types — `TokenInfo[T]`, `LanguageSpec[T, K]`, and `ParserContext[T, K]` — along with a `parse_with` entry point. The existing Lambda Calculus parser is then migrated to use `ParserContext` as a reference implementation proving the API is sufficient. Phase 2 (combinator helpers, separate-repo extraction) is out of scope.

**Tech Stack:** MoonBit, `moon` build tool. Packages use `moon.pkg` files (not `.json`). Run `moon test` from `parser/` root. Tests use `inspect!` for snapshots. No new dependencies needed — `src/core/` imports `dowdiness/parser/green-tree` directly.

---

### Task 1: Create `src/core/` package skeleton

**Files:**
- Create: `src/core/moon.pkg`
- Create: `src/core/lib.mbt`

**Step 1: Create the package import file**

```
// src/core/moon.pkg
import {
  "dowdiness/parser/green-tree" @green_tree,
}
```

**Step 2: Create a placeholder lib file**

```moonbit
// src/core/lib.mbt
// Generic parser infrastructure — ParserContext[T, K]
```

**Step 3: Verify the module still builds**

Run: `moon check`
Expected: no errors

**Step 4: Commit**

```bash
git add src/core/moon.pkg src/core/lib.mbt
git commit -m "feat(core): add parser-core package skeleton"
```

---

### Task 2: Implement `TokenInfo[T]`, `Diagnostic`, and `LanguageSpec[T, K]`

**Files:**
- Modify: `src/core/lib.mbt`

**Step 1: Write the failing test first**

Add to `src/core/lib.mbt`:

```moonbit
///|
test "TokenInfo stores token with position" {
  let info : TokenInfo[String] = { token: "hello", start: 0, end: 5 }
  inspect!(info.start, content="0")
  inspect!(info.end, content="5")
  inspect!(info.token, content="\"hello\"")
}

///|
test "Diagnostic stores message and position" {
  let d : Diagnostic = { message: "unexpected token", start: 3, end: 7 }
  inspect!(d.message, content="\"unexpected token\"")
}
```

**Step 2: Run test to verify it fails**

Run: `moon test --package dowdiness/parser/core`
Expected: FAIL — `TokenInfo` not defined

**Step 3: Implement the types**

Add before the tests in `src/core/lib.mbt`:

```moonbit
///|
/// Generic token with source position. T is the language-specific token type.
pub struct TokenInfo[T] {
  token : T
  start : Int // byte offset, inclusive
  end   : Int // byte offset, exclusive
} derive(Show)

///|
/// A parse diagnostic (error or warning) with source position.
pub struct Diagnostic {
  message : String
  start   : Int
  end     : Int
} derive(Show)

///|
/// Describes one language to the generic parser infrastructure.
/// Create one instance at module init — it is reused across all parses.
///
/// Fields:
///   kind_to_raw     — maps your SyntaxKind to the green tree's RawKind (an Int)
///   token_is_eof    — returns true for the end-of-input sentinel token
///   tokens_equal    — equality check (needed because T has no Eq constraint)
///   whitespace_kind — the SyntaxKind for whitespace trivia nodes
///   error_kind      — the SyntaxKind for error tokens/nodes
///   root_kind       — the SyntaxKind for the root node (e.g. SourceFile)
///   eof_token       — the T value returned when past end of input
pub struct LanguageSpec[T, K] {
  kind_to_raw     : (K) -> @green_tree.RawKind
  token_is_eof    : (T) -> Bool
  tokens_equal    : (T, T) -> Bool
  whitespace_kind : K
  error_kind      : K
  root_kind       : K
  eof_token       : T
}
```

**Step 4: Run test to verify it passes**

Run: `moon test --package dowdiness/parser/core`
Expected: PASS

**Step 5: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add TokenInfo[T], Diagnostic, LanguageSpec[T,K]"
```

---

### Task 3: Implement `ParserContext[T, K]` struct and constructor

**Files:**
- Modify: `src/core/lib.mbt`

**Step 1: Write failing test**

```moonbit
///|
test "ParserContext can be constructed" {
  let spec : LanguageSpec[String, Int] = {
    kind_to_raw     : fn(k) { @green_tree.RawKind(k) },
    token_is_eof    : fn(t) { t == "EOF" },
    tokens_equal    : fn(a, b) { a == b },
    whitespace_kind : 0,
    error_kind      : 1,
    root_kind       : 2,
    eof_token       : "EOF",
  }
  let tokens : Array[TokenInfo[String]] = [{ token: "hello", start: 0, end: 5 }]
  let ctx = ParserContext::new(tokens, "hello", spec)
  inspect!(ctx.position, content="0")
}
```

Run: `moon test --package dowdiness/parser/core`
Expected: FAIL — `ParserContext` not defined

**Step 2: Implement the struct and constructor**

```moonbit
///|
/// Core parser state. Grammar functions receive this and call methods on it.
/// T = token type, K = syntax-kind type.
pub struct ParserContext[T, K] {
  spec           : LanguageSpec[T, K]
  tokens         : Array[TokenInfo[T]]
  source         : String
  mut position   : Int
  mut last_end   : Int
  events         : @green_tree.EventBuffer
  errors         : Array[Diagnostic]
  mut error_count : Int
  mut open_nodes  : Int
}

///|
pub fn ParserContext::new[T, K](
  tokens : Array[TokenInfo[T]],
  source : String,
  spec   : LanguageSpec[T, K],
) -> ParserContext[T, K] {
  {
    spec,
    tokens,
    source,
    position    : 0,
    last_end    : 0,
    events      : @green_tree.EventBuffer::new(),
    errors      : [],
    error_count : 0,
    open_nodes  : 0,
  }
}
```

**Step 3: Run test to verify it passes**

Run: `moon test --package dowdiness/parser/core`
Expected: PASS

**Step 4: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add ParserContext[T,K] struct and constructor"
```

---

### Task 4: Implement peek/at/peek_info methods

**Files:**
- Modify: `src/core/lib.mbt`

**Step 1: Write failing tests**

```moonbit
///|
test "peek returns current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect!(ctx.peek(), content="\"a\"")
}

///|
test "peek returns eof when past end" {
  let (spec, _) = make_test_fixtures()
  let ctx = ParserContext::new([], "", spec)
  inspect!(ctx.peek(), content="\"EOF\"")
}

///|
test "at matches current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect!(ctx.at("a"), content="true")
  inspect!(ctx.at("b"), content="false")
}
```

Add the test fixture helper (private, test-only) at the top of the test section:

```moonbit
///|
fn make_test_fixtures() -> (LanguageSpec[String, Int], Array[TokenInfo[String]]) {
  let spec : LanguageSpec[String, Int] = {
    kind_to_raw     : fn(k) { @green_tree.RawKind(k) },
    token_is_eof    : fn(t) { t == "EOF" },
    tokens_equal    : fn(a, b) { a == b },
    whitespace_kind : 0,
    error_kind      : 1,
    root_kind       : 2,
    eof_token       : "EOF",
  }
  let tokens = [
    { token: "a", start: 0, end: 1 },
    { token: "b", start: 1, end: 2 },
  ]
  (spec, tokens)
}
```

Run: `moon test --package dowdiness/parser/core`
Expected: FAIL — `peek` not defined

**Step 2: Implement the methods**

```moonbit
///|
/// Return the current token without consuming it.
pub fn ParserContext::peek[T, K](self : ParserContext[T, K]) -> T {
  if self.position < self.tokens.length() {
    self.tokens[self.position].token
  } else {
    self.spec.eof_token
  }
}

///|
/// Return current token with position info.
pub fn ParserContext::peek_info[T, K](
  self : ParserContext[T, K],
) -> TokenInfo[T] {
  if self.position < self.tokens.length() {
    self.tokens[self.position]
  } else {
    let end = self.source.length()
    { token: self.spec.eof_token, start: end, end }
  }
}

///|
/// Return true if the current token equals the given token.
pub fn ParserContext::at[T, K](self : ParserContext[T, K], token : T) -> Bool {
  (self.spec.tokens_equal)(self.peek(), token)
}

///|
/// Return true if at end of input.
pub fn ParserContext::at_eof[T, K](self : ParserContext[T, K]) -> Bool {
  (self.spec.token_is_eof)(self.peek())
}
```

**Step 3: Run tests**

Run: `moon test --package dowdiness/parser/core`
Expected: PASS

**Step 4: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add peek/at/peek_info/at_eof methods"
```

---

### Task 5: Implement emit and node methods

These are the methods grammar code calls most frequently. No new tests needed here — the integration test in Task 7 covers them end-to-end.

**Files:**
- Modify: `src/core/lib.mbt`

**Step 1: Implement the 6 methods**

```moonbit
///|
/// Extract source text for a token from the source string.
pub fn ParserContext::token_text[T, K](
  self : ParserContext[T, K],
  info : TokenInfo[T],
) -> String {
  let slice : StringView = self.source[info.start:info.end] catch { _ => "" }
  slice.to_string()
}

///|
fn ParserContext::emit_whitespace_before[T, K](
  self : ParserContext[T, K],
  info : TokenInfo[T],
) -> Unit {
  if info.start > self.last_end {
    let ws_text : StringView = self.source[self.last_end:info.start] catch {
        _ => ""
      }
    self.events.push(
      @green_tree.ParseEvent::Token(
        (self.spec.kind_to_raw)(self.spec.whitespace_kind),
        ws_text.to_string(),
      ),
    )
  }
}

///|
/// Consume the current token and emit it as a leaf in the green tree.
pub fn ParserContext::emit_token[T, K](
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  let info = self.peek_info()
  self.emit_whitespace_before(info)
  let text = self.token_text(info)
  self.events.push(
    @green_tree.ParseEvent::Token((self.spec.kind_to_raw)(kind), text),
  )
  self.last_end = info.end
  self.position = self.position + 1
}

///|
/// Open a new node. Must be followed by finish_node().
pub fn ParserContext::start_node[T, K](
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.open_nodes = self.open_nodes + 1
  self.events.push(@green_tree.StartNode((self.spec.kind_to_raw)(kind)))
}

///|
/// Close the most recently opened node.
pub fn ParserContext::finish_node[T, K](self : ParserContext[T, K]) -> Unit {
  if self.open_nodes <= 0 {
    abort("finish_node: no matching start_node")
  }
  self.open_nodes = self.open_nodes - 1
  self.events.push(@green_tree.FinishNode)
}

///|
/// Reserve a placeholder that can later be claimed by start_at.
/// Used for retroactive wrapping (e.g. binary expressions, applications).
pub fn ParserContext::mark[T, K](self : ParserContext[T, K]) -> Int {
  self.events.mark()
}

///|
/// Retroactively open a node at a previously marked position.
pub fn ParserContext::start_at[T, K](
  self : ParserContext[T, K],
  mark : Int,
  kind : K,
) -> Unit {
  self.events.start_at(mark, (self.spec.kind_to_raw)(kind))
  self.open_nodes = self.open_nodes + 1
}
```

**Step 2: Verify no compilation errors**

Run: `moon check`
Expected: no errors

**Step 3: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add emit_token, start_node, finish_node, mark, start_at"
```

---

### Task 6: Implement error methods

**Files:**
- Modify: `src/core/lib.mbt`

**Step 1: Implement**

```moonbit
///|
/// Record a diagnostic at the current position. Does not consume a token.
pub fn ParserContext::error[T, K](
  self : ParserContext[T, K],
  msg  : String,
) -> Unit {
  let info = self.peek_info()
  self.errors.push({ message: msg, start: info.start, end: info.end })
  self.error_count = self.error_count + 1
}

///|
/// Consume the current token and emit it as an error token (for error recovery).
pub fn ParserContext::bump_error[T, K](self : ParserContext[T, K]) -> Unit {
  let info = self.peek_info()
  self.emit_whitespace_before(info)
  let text = self.token_text(info)
  self.events.push(
    @green_tree.ParseEvent::Token(
      (self.spec.kind_to_raw)(self.spec.error_kind),
      text,
    ),
  )
  self.last_end = info.end
  self.position = self.position + 1
}
```

**Step 2: Verify no compilation errors**

Run: `moon check`
Expected: no errors

**Step 3: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add error and bump_error methods"
```

---

### Task 7: Implement `parse_with` entry point and integration test

This is the public API. The test uses a minimal two-token test language (numbers and `+`) — deliberately different from Lambda to prove the API is truly generic.

**Files:**
- Modify: `src/core/lib.mbt`

**Step 1: Write the integration test first**

The test language: integers and `+`. Grammar: `Expr → Int ('+' Int)*`

```moonbit
///|
// Test language: integers and '+' only
enum TestTok {
  Num(Int)
  Plus
  TokEof
} derive(Eq, Show)

///|
enum TestKind {
  KNum    // 0
  KPlus   // 1
  KExpr   // 2
  KRoot   // 3
  KWs     // 4
  KErr    // 5
} derive(Show)

///|
fn test_kind_raw(k : TestKind) -> @green_tree.RawKind {
  let n = match k {
    KNum  => 0
    KPlus => 1
    KExpr => 2
    KRoot => 3
    KWs   => 4
    KErr  => 5
  }
  @green_tree.RawKind(n)
}

///|
fn test_tokenize(src : String) -> Array[TokenInfo[TestTok]] {
  let result : Array[TokenInfo[TestTok]] = []
  let mut i = 0
  while i < src.length() {
    let c = src.char_at(i)
    if c == ' ' {
      i = i + 1
    } else if c >= '0' && c <= '9' {
      let start = i
      let mut n = c.to_int() - 48
      i = i + 1
      while i < src.length() && src.char_at(i) >= '0' && src.char_at(i) <= '9' {
        n = n * 10 + src.char_at(i).to_int() - 48
        i = i + 1
      }
      result.push({ token: TestTok::Num(n), start, end: i })
    } else if c == '+' {
      result.push({ token: TestTok::Plus, start: i, end: i + 1 })
      i = i + 1
    } else {
      i = i + 1
    }
  }
  result
}

///|
let test_spec : LanguageSpec[TestTok, TestKind] = {
  kind_to_raw     : test_kind_raw,
  token_is_eof    : fn(t) { t == TestTok::TokEof },
  tokens_equal    : fn(a, b) { a == b },
  whitespace_kind : KWs,
  error_kind      : KErr,
  root_kind       : KRoot,
  eof_token       : TestTok::TokEof,
}

///|
fn test_grammar(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  let mark = ctx.mark()
  match ctx.peek() {
    TestTok::Num(_) => ctx.emit_token(KNum)
    _ => {
      ctx.error("expected number")
      return
    }
  }
  if ctx.at(TestTok::Plus) {
    ctx.start_at(mark, KExpr)
    while ctx.at(TestTok::Plus) {
      ctx.emit_token(KPlus)
      match ctx.peek() {
        TestTok::Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected number after +")
      }
    }
    ctx.finish_node()
  }
}

///|
test "parse_with: simple number" {
  let (tree, errors) = parse_with("42", test_spec, test_tokenize, test_grammar)
  inspect!(errors.length(), content="0")
  inspect!(tree.text_len, content="2")
}

///|
test "parse_with: addition expression" {
  let (tree, errors) = parse_with("1 + 2 + 3", test_spec, test_tokenize, test_grammar)
  inspect!(errors.length(), content="0")
  inspect!(tree.text_len, content="9")
}

///|
test "parse_with: records errors on bad input" {
  let (_, errors) = parse_with("+", test_spec, test_tokenize, test_grammar)
  inspect!(errors.length(), content="1")
  inspect!(errors[0].message, content="\"expected number\"")
}
```

Run: `moon test --package dowdiness/parser/core`
Expected: FAIL — `parse_with` not defined

**Step 2: Implement `parse_with`**

```moonbit
///|
/// Parse a source string using the given language spec and grammar function.
/// Returns the immutable green tree and any parse diagnostics.
///
/// tokenize — converts source to tokens (raises on unrecoverable lex errors)
/// grammar  — the entry-point parse function; calls ctx methods to build the tree
pub fn parse_with[T, K](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@green_tree.GreenNode, Array[Diagnostic]) {
  let tokens = tokenize(source)
  let ctx = ParserContext::new(tokens, source, spec)
  grammar(ctx)
  if ctx.open_nodes != 0 {
    abort(
      "parse_with: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
  // Emit any trailing whitespace after the last token
  if ctx.last_end < source.length() {
    let ws_text : StringView = source[ctx.last_end:source.length()] catch {
        _ => ""
      }
    ctx.events.push(
      @green_tree.ParseEvent::Token(
        (spec.kind_to_raw)(spec.whitespace_kind),
        ws_text.to_string(),
      ),
    )
  }
  let tree = @green_tree.build_tree(
    ctx.events.events,
    (spec.kind_to_raw)(spec.root_kind),
    trivia_kind=Some((spec.kind_to_raw)(spec.whitespace_kind)),
  )
  (tree, ctx.errors)
}

///|
/// Raising variant — same as parse_with but the tokenize function may raise.
pub fn parse_with_raise[T, K](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]] raise,
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@green_tree.GreenNode, Array[Diagnostic]) raise {
  let tokens = tokenize(source)
  let ctx = ParserContext::new(tokens, source, spec)
  grammar(ctx)
  if ctx.open_nodes != 0 {
    abort(
      "parse_with_raise: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
  if ctx.last_end < source.length() {
    let ws_text : StringView = source[ctx.last_end:source.length()] catch {
        _ => ""
      }
    ctx.events.push(
      @green_tree.ParseEvent::Token(
        (spec.kind_to_raw)(spec.whitespace_kind),
        ws_text.to_string(),
      ),
    )
  }
  let tree = @green_tree.build_tree(
    ctx.events.events,
    (spec.kind_to_raw)(spec.root_kind),
    trivia_kind=Some((spec.kind_to_raw)(spec.whitespace_kind)),
  )
  (tree, ctx.errors)
}
```

**Step 3: Run tests**

Run: `moon test --package dowdiness/parser/core`
Expected: PASS on all 3 integration tests

**Step 4: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add parse_with and parse_with_raise entry points"
```

---

### Task 8: Add `core` import to `src/parser/moon.pkg`

**Files:**
- Modify: `src/parser/moon.pkg`

**Step 1: Add the import**

Edit `src/parser/moon.pkg` to add `"dowdiness/parser/core" @core` to the import list:

```
import {
  "dowdiness/parser/token",
  "dowdiness/parser/range",
  "dowdiness/parser/term",
  "dowdiness/parser/lexer",
  "dowdiness/parser/syntax",
  "dowdiness/parser/green-tree" @green_tree,
  "dowdiness/parser/core" @core,
  "moonbitlang/core/strconv",
}

import {
  "moonbitlang/core/quickcheck",
} for "test"
```

**Step 2: Verify the module still builds**

Run: `moon check`
Expected: no errors

**Step 3: Commit**

```bash
git add src/parser/moon.pkg
git commit -m "feat(parser): import core package"
```

---

### Task 9: Create `src/parser/lambda_spec.mbt`

This file defines the `LanguageSpec` for Lambda Calculus — the bridge between the generic `core` API and the Lambda-specific types.

**Files:**
- Create: `src/parser/lambda_spec.mbt`

**Step 1: Create the file**

```moonbit
// Lambda Calculus language specification for the generic parser infrastructure.

///|
/// The LanguageSpec for Lambda Calculus.
/// Created once at module init, reused across all parses (zero per-parse allocation).
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = {
  kind_to_raw     : @syntax.SyntaxKind::to_raw,
  token_is_eof    : fn(t) { t == @token.EOF },
  tokens_equal    : fn(a, b) { a == b },
  whitespace_kind : @syntax.WhitespaceToken,
  error_kind      : @syntax.ErrorToken,
  root_kind       : @syntax.SourceFile,
  eof_token       : @token.EOF,
}
```

**Step 2: Verify it compiles**

Run: `moon check`
Expected: no errors

**Step 3: Commit**

```bash
git add src/parser/lambda_spec.mbt
git commit -m "feat(parser): add lambda_spec bridging LanguageSpec to Lambda types"
```

---

### Task 10: Migrate `GreenParser` → `ParserContext` in `green_parser.mbt`

This is the largest task. The `GreenParser` struct is replaced by `@core.ParserContext`. All `self.*` calls map directly to `ctx.*` equivalents. The rename map:

| Old (`self.`) | New (`ctx.`) |
|---|---|
| `self.mark_node()` | `ctx.mark()` |
| `self.start_marked_node(m, k)` | `ctx.start_at(m, k)` |
| `self.start_node(k)` | `ctx.start_node(k)` |
| `self.finish_node()` | `ctx.finish_node()` |
| `self.emit_token(k)` | `ctx.emit_token(k)` |
| `self.peek()` | `ctx.peek()` |
| `self.peek_info()` | `ctx.peek_info()` |
| `self.error(msg, tok, s, e)` | `ctx.error(msg)` (position auto-captured) |
| `self.bump_error()` | `ctx.bump_error()` |
| `self.events.push(...)` | direct (internal only, move to ctx helper) |

**Files:**
- Modify: `src/parser/green_parser.mbt`

**Step 1: Add a type alias at the top of `green_parser.mbt` for readability**

```moonbit
///|
// Type alias for the Lambda parser context — avoids repeating the long type every time.
type LambdaCtx = @core.ParserContext[@token.Token, @syntax.SyntaxKind]
```

**Step 2: Replace `GreenParser::new` / `new_with_cursor` with context construction**

Replace the two `GreenParser::new*` functions and the `GreenParser` struct definition with a constructor that returns `LambdaCtx`:

```moonbit
///|
fn make_lambda_ctx(
  tokens : Array[@core.TokenInfo[@token.Token]],
  source : String,
) -> LambdaCtx {
  @core.ParserContext::new(tokens, source, lambda_spec)
}
```

Note: the `cursor` field is deferred — incremental parsing will be addressed in a follow-up. The `parse_green_with_cursor` and `parse_green_recover_with_tokens` functions can temporarily call `parse_green_recover` (non-incremental) until cursor support is added.

**Step 3: Rewrite `parse_green_recover` to use `parse_with_raise`**

```moonbit
///|
pub fn parse_green_recover(
  source    : String,
  interner? : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[@core.Diagnostic]) raise @lexer.TokenizationError {
  let raw_tokens = @lexer.tokenize(source)
  // Convert @token.TokenInfo to @core.TokenInfo[@token.Token]
  let tokens = raw_tokens.map(fn(ti) {
    @core.TokenInfo::{ token: ti.token, start: ti.start, end: ti.end }
  })
  let (tree, errors) = @core.parse_with_raise(
    source,
    lambda_spec,
    fn(_) { tokens },  // tokenize already done above
    parse_lambda_root,
  )
  // Handle interner separately if provided (post-process the tree)
  ignore(interner)
  (tree, errors)
}
```

**Step 4: Convert each `GreenParser::parse_*` method to a free function taking `LambdaCtx`**

Rename signatures from:
```moonbit
fn GreenParser::parse_binary_op(self : GreenParser) -> Unit
```
to:
```moonbit
fn parse_binary_op(ctx : LambdaCtx) -> Unit
```

And replace all `self.*` with `ctx.*` using the rename map above. The `at_stop_token` logic stays as a local helper:

```moonbit
fn at_stop_token(ctx : LambdaCtx) -> Bool {
  match ctx.peek() {
    @token.RightParen | @token.Then | @token.Else | @token.EOF => true
    _ => false
  }
}
```

The `parse_source_file` method becomes `parse_lambda_root` — the grammar entry point passed to `parse_with_raise`.

**Step 5: Run the full test suite**

Run: `moon test`
Expected: All tests that passed before still pass.

If any tests check `ParseDiagnostic` fields that included a `token` field, update them: `Diagnostic` in `core` has `message`, `start`, `end` only (no `token`). Search for `ParseDiagnostic` usages:

```bash
grep -r "ParseDiagnostic" src/
```

Update any remaining references to use `@core.Diagnostic`.

**Step 6: Commit**

```bash
git add src/parser/green_parser.mbt
git commit -m "refactor(parser): migrate GreenParser to ParserContext from core"
```

---

### Task 11: Update `parse_green` public API to match new internals

**Files:**
- Modify: `src/parser/green_parser.mbt`

`parse_green` (the strict/raising version) currently converts `errors[0]` to `ParseError`. Check that it still works after the migration — `ParseDiagnostic.token` is gone, so the `ParseError` constructor call needs updating.

**Step 1: Check and update the strict wrapper**

Old:
```moonbit
pub fn parse_green(source : String) -> @green_tree.GreenNode raise {
  let (green, errors) = parse_green_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, diag.token)  // ← diag.token no longer exists
  }
  green
}
```

New (`ParseError` now just takes a String and position):
```moonbit
pub fn parse_green(source : String) -> @green_tree.GreenNode raise {
  let (green, errors) = parse_green_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, @token.EOF)  // token field unused in practice
  }
  green
}
```

Or update `ParseError` to not carry a token — check if any tests match on the token field. Run:

```bash
grep -r "ParseError" src/
```

**Step 2: Run full test suite**

Run: `moon test`
Expected: PASS

Run: `moon bench --release`
Expected: no regressions (compare against last benchmark snapshot in `docs/benchmark_history.md`)

**Step 3: Update interfaces**

```bash
moon info && moon fmt
git diff src/**/*.mbti
```

Verify the public API exposed in `.mbti` files matches intent — new `@core.TokenInfo`, `@core.Diagnostic`, `@core.LanguageSpec`, `@core.ParserContext` types should appear in `src/core/pkg.generated.mbti`.

**Step 4: Final commit**

```bash
git add src/
git commit -m "feat: complete generic ParserContext migration, Lambda parser as reference impl"
```

---

## Out of Scope (Phase 2)

The following are intentionally deferred:

- **Incremental cursor support**: `parse_with_cursor` wrapping `ReuseCursor` as a generic type — `ReuseCursor[T]` needs to be parameterized and moved to `core`
- **Combinator helpers**: `node()`, `repeat_while()`, `choice()` thin wrappers over `ParserContext`
- **Separate repo extraction**: Publishing `parser-core` as `dowdiness/parser-core` with its own `moon.mod.json`
- **Interner support**: `parse_with_raise` currently ignores the `interner?` parameter; restoring this requires adding interner to `parse_with`'s signature or to `LanguageSpec`
