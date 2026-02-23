// Generic parser infrastructure — ParserContext[T, K]

///|
/// Generic token with source position. T is the language-specific token type.
pub struct TokenInfo[T] {
  token : T
  start : Int // byte offset, inclusive
  end : Int // byte offset, exclusive
} derive(Show)

///|
/// A parse diagnostic (error or warning) with source position.
pub struct Diagnostic {
  message : String
  start : Int
  end : Int
} derive(Show)

///|
/// Describes one language to the generic parser infrastructure.
/// Create one instance at module init — it is reused across all parses.
///
/// Fields:
///   kind_to_raw     — maps your SyntaxKind to the green tree's RawKind (an Int)
///   token_is_eof    — returns true for the end-of-input sentinel token
///   token_is_trivia — returns true for whitespace/trivia tokens to skip in peek
///   tokens_equal    — equality check (needed because T has no Eq constraint)
///   whitespace_kind — the SyntaxKind for whitespace trivia nodes in the tree
///   error_kind      — the SyntaxKind for error tokens/nodes
///   root_kind       — the SyntaxKind for the root node (e.g. SourceFile)
///   eof_token       — the T value returned when past end of input
pub struct LanguageSpec[T, K] {
  kind_to_raw : (K) -> @green_tree.RawKind
  token_is_eof : (T) -> Bool
  token_is_trivia : (T) -> Bool
  tokens_equal : (T, T) -> Bool
  whitespace_kind : K
  error_kind : K
  root_kind : K
  eof_token : T
}

///|
/// Construct a TokenInfo. Use this from outside the core package.
pub fn[T] TokenInfo::new(token : T, start : Int, end : Int) -> TokenInfo[T] {
  { token, start, end }
}

///|
/// Construct a LanguageSpec. Use this from outside the core package.
pub fn[T, K] LanguageSpec::new(
  kind_to_raw : (K) -> @green_tree.RawKind,
  token_is_eof : (T) -> Bool,
  token_is_trivia : (T) -> Bool,
  tokens_equal : (T, T) -> Bool,
  whitespace_kind : K,
  error_kind : K,
  root_kind : K,
  eof_token : T,
) -> LanguageSpec[T, K] {
  {
    kind_to_raw,
    token_is_eof,
    token_is_trivia,
    tokens_equal,
    whitespace_kind,
    error_kind,
    root_kind,
    eof_token,
  }
}

///|
/// Core parser state. Grammar functions receive this and call methods on it.
/// T = token type, K = syntax-kind type.
pub struct ParserContext[T, K] {
  spec : LanguageSpec[T, K]
  tokens : Array[TokenInfo[T]]
  source : String
  mut position : Int
  events : @green_tree.EventBuffer
  errors : Array[Diagnostic]
  mut error_count : Int
  mut open_nodes : Int
}

///|
pub fn[T, K] ParserContext::new(
  tokens : Array[TokenInfo[T]],
  source : String,
  spec : LanguageSpec[T, K],
) -> ParserContext[T, K] {
  {
    spec,
    tokens,
    source,
    position: 0,
    events: @green_tree.EventBuffer::new(),
    errors: [],
    error_count: 0,
    open_nodes: 0,
  }
}

///|
/// Return the next non-trivia token without consuming it.
pub fn[T, K] ParserContext::peek(self : ParserContext[T, K]) -> T {
  let mut pos = self.position
  while pos < self.tokens.length() {
    let t = self.tokens[pos].token
    if (self.spec.token_is_trivia)(t) {
      pos = pos + 1
    } else {
      return t
    }
  }
  self.spec.eof_token
}

///|
/// Return the TokenInfo for the next non-trivia token.
pub fn[T, K] ParserContext::peek_info(
  self : ParserContext[T, K],
) -> TokenInfo[T] {
  let mut pos = self.position
  while pos < self.tokens.length() {
    let info = self.tokens[pos]
    if (self.spec.token_is_trivia)(info.token) {
      pos = pos + 1
    } else {
      return info
    }
  }
  let end = self.source.length()
  { token: self.spec.eof_token, start: end, end }
}

///|
/// Return true if the current non-trivia token equals the given token.
pub fn[T, K] ParserContext::at(self : ParserContext[T, K], token : T) -> Bool {
  (self.spec.tokens_equal)(self.peek(), token)
}

///|
/// Return true if at end of input (ignoring trivia).
pub fn[T, K] ParserContext::at_eof(self : ParserContext[T, K]) -> Bool {
  (self.spec.token_is_eof)(self.peek())
}

///|
/// Extract source text for a token from the source string.
pub fn[T, K] ParserContext::token_text(
  self : ParserContext[T, K],
  info : TokenInfo[T],
) -> String {
  let slice : StringView = self.source[info.start:info.end] catch { _ => "" }
  slice.to_string()
}

///|
/// Emit all consecutive trivia tokens at current position to the event stream,
/// advancing position past each one. Call this before emitting syntactic tokens,
/// and at the end of the top-level grammar function before returning.
pub fn[T, K] ParserContext::flush_trivia(self : ParserContext[T, K]) -> Unit {
  while self.position < self.tokens.length() {
    let info = self.tokens[self.position]
    if (self.spec.token_is_trivia)(info.token) {
      let text = self.token_text(info)
      self.events.push(
        @green_tree.ParseEvent::Token(
          (self.spec.kind_to_raw)(self.spec.whitespace_kind),
          text,
        ),
      )
      self.position = self.position + 1
    } else {
      break
    }
  }
}

///|
/// Consume the current token and emit it as a leaf in the green tree.
/// Automatically flushes leading trivia before the token.
pub fn[T, K] ParserContext::emit_token(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.flush_trivia()
  let info = self.peek_info()
  let text = self.token_text(info)
  self.events.push(
    @green_tree.ParseEvent::Token((self.spec.kind_to_raw)(kind), text),
  )
  self.position = self.position + 1
}

///|
/// Open a new node. Must be followed by finish_node().
pub fn[T, K] ParserContext::start_node(
  self : ParserContext[T, K],
  kind : K,
) -> Unit {
  self.open_nodes = self.open_nodes + 1
  self.events.push(@green_tree.StartNode((self.spec.kind_to_raw)(kind)))
}

///|
/// Close the most recently opened node.
pub fn[T, K] ParserContext::finish_node(self : ParserContext[T, K]) -> Unit {
  if self.open_nodes <= 0 {
    abort("finish_node: no matching start_node")
  }
  self.open_nodes = self.open_nodes - 1
  self.events.push(@green_tree.FinishNode)
}

///|
/// Reserve a placeholder that can later be claimed by start_at.
/// Used for retroactive wrapping (e.g. binary expressions, applications).
pub fn[T, K] ParserContext::mark(self : ParserContext[T, K]) -> Int {
  self.events.mark()
}

///|
/// Retroactively open a node at a previously marked position.
pub fn[T, K] ParserContext::start_at(
  self : ParserContext[T, K],
  mark : Int,
  kind : K,
) -> Unit {
  self.events.start_at(mark, (self.spec.kind_to_raw)(kind))
  self.open_nodes = self.open_nodes + 1
}

///|
/// Record a diagnostic at the current position. Does not consume a token.
pub fn[T, K] ParserContext::error(
  self : ParserContext[T, K],
  msg : String,
) -> Unit {
  let info = self.peek_info()
  self.errors.push({ message: msg, start: info.start, end: info.end })
  self.error_count = self.error_count + 1
}

///|
/// Consume the current token and emit it as an error token (for error recovery).
/// Automatically flushes leading trivia before the token.
pub fn[T, K] ParserContext::bump_error(self : ParserContext[T, K]) -> Unit {
  self.flush_trivia()
  let info = self.peek_info()
  let text = self.token_text(info)
  self.events.push(
    @green_tree.ParseEvent::Token(
      (self.spec.kind_to_raw)(self.spec.error_kind),
      text,
    ),
  )
  self.position = self.position + 1
}

// ─── Tests ───────────────────────────────────────────────────────────────────

///|
test "TokenInfo stores token with position" {
  let info : TokenInfo[String] = { token: "hello", start: 0, end: 5 }
  inspect(info.start, content="0")
  inspect(info.end, content="5")
  inspect(info.token, content="hello")
}

///|
test "Diagnostic stores message and position" {
  let d : Diagnostic = { message: "unexpected token", start: 3, end: 7 }
  inspect(d.message, content="unexpected token")
}

///|
fn make_test_fixtures() -> (LanguageSpec[String, Int], Array[TokenInfo[String]]) {
  let spec : LanguageSpec[String, Int] = {
    kind_to_raw: fn(k) { @green_tree.RawKind(k) },
    token_is_eof: fn(t) { t == "EOF" },
    token_is_trivia: fn(_) { false },
    tokens_equal: fn(a, b) { a == b },
    whitespace_kind: 0,
    error_kind: 1,
    root_kind: 2,
    eof_token: "EOF",
  }
  let tokens = [
    { token: "a", start: 0, end: 1 },
    { token: "b", start: 1, end: 2 },
  ]
  (spec, tokens)
}

///|
test "ParserContext can be constructed" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.position, content="0")
}

///|
test "peek returns current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.peek(), content="a")
}

///|
test "peek returns eof when past end" {
  let (spec, _) = make_test_fixtures()
  let ctx = ParserContext::new([], "", spec)
  inspect(ctx.peek(), content="EOF")
}

///|
test "peek skips trivia tokens" {
  let spec : LanguageSpec[String, Int] = {
    kind_to_raw: fn(k) { @green_tree.RawKind(k) },
    token_is_eof: fn(t) { t == "EOF" },
    token_is_trivia: fn(t) { t == " " },
    tokens_equal: fn(a, b) { a == b },
    whitespace_kind: 0,
    error_kind: 1,
    root_kind: 2,
    eof_token: "EOF",
  }
  let tokens = [
    { token: " ", start: 0, end: 1 },
    { token: " ", start: 1, end: 2 },
    { token: "x", start: 2, end: 3 },
  ]
  let ctx = ParserContext::new(tokens, "  x", spec)
  inspect(ctx.peek(), content="x")
}

///|
test "at matches current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.at("a"), content="true")
  inspect(ctx.at("b"), content="false")
}

// ─── parse_with ───────────────────────────────────────────────────────────────

///|
/// Parse a source string using the given language spec and grammar function.
/// Returns the immutable green tree and any parse diagnostics.
///
/// tokenize — converts source to a flat token array (including trivia tokens)
/// grammar  — the entry-point parse function; calls ctx methods to build the tree
pub fn[T, K] parse_with(
  source : String,
  spec : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar : (ParserContext[T, K]) -> Unit,
) -> (@green_tree.GreenNode, Array[Diagnostic]) {
  let tokens = tokenize(source)
  let ctx = ParserContext::new(tokens, source, spec)
  grammar(ctx)
  ctx.flush_trivia()
  if ctx.open_nodes != 0 {
    abort(
      "parse_with: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
  let tree = @green_tree.build_tree(
    ctx.events.events,
    (spec.kind_to_raw)(spec.root_kind),
    trivia_kind=Some((spec.kind_to_raw)(spec.whitespace_kind)),
  )
  (tree, ctx.errors)
}

// ─── Integration test: minimal two-token language ─────────────────────────────

///|
// Test language: integers and '+' only (with whitespace)
enum TestTok {
  Num(Int)
  Plus
  Ws
  TokEof
} derive(Eq, Show)

///|
enum TestKind {
  KNum
  KPlus
  KExpr
  KRoot
  KWs
  KErr
} derive(Show)

///|
fn test_kind_raw(k : TestKind) -> @green_tree.RawKind {
  let n = match k {
    KNum => 0
    KPlus => 1
    KExpr => 2
    KRoot => 3
    KWs => 4
    KErr => 5
  }
  @green_tree.RawKind(n)
}

///|
fn test_tokenize(src : String) -> Array[TokenInfo[TestTok]] {
  let result : Array[TokenInfo[TestTok]] = []
  let mut i = 0
  while i < src.length() {
    let code = src.code_unit_at(i).to_int()
    if code == 32 {
      // space
      let start = i
      while i < src.length() && src.code_unit_at(i).to_int() == 32 {
        i = i + 1
      }
      result.push({ token: TestTok::Ws, start, end: i })
    } else if code >= 48 && code <= 57 {
      // digit
      let start = i
      let mut n = code - 48
      i = i + 1
      while i < src.length() {
        let d = src.code_unit_at(i).to_int()
        if d >= 48 && d <= 57 {
          n = n * 10 + d - 48
          i = i + 1
        } else {
          break
        }
      }
      result.push({ token: TestTok::Num(n), start, end: i })
    } else if code == 43 {
      // '+'
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
  kind_to_raw: test_kind_raw,
  token_is_eof: fn(t) { t == TestTok::TokEof },
  token_is_trivia: fn(t) { t == TestTok::Ws },
  tokens_equal: fn(a, b) { a == b },
  whitespace_kind: KWs,
  error_kind: KErr,
  root_kind: KRoot,
  eof_token: TestTok::TokEof,
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
  inspect(errors.length(), content="0")
  inspect(tree.text_len, content="2")
}

///|
test "parse_with: addition expression" {
  let (tree, errors) = parse_with(
    "1 + 2 + 3", test_spec, test_tokenize, test_grammar,
  )
  inspect(errors.length(), content="0")
  inspect(tree.text_len, content="9")
}

///|
test "parse_with: records errors on bad input" {
  let (_, errors) = parse_with("+", test_spec, test_tokenize, test_grammar)
  inspect(errors.length(), content="1")
  inspect(errors[0].message, content="expected number")
}
