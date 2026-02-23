// Generic parser infrastructure — ParserContext[T, K]

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

///|
/// Core parser state. Grammar functions receive this and call methods on it.
/// T = token type, K = syntax-kind type.
pub struct ParserContext[T, K] {
  spec            : LanguageSpec[T, K]
  tokens          : Array[TokenInfo[T]]
  source          : String
  mut position    : Int
  mut last_end    : Int
  events          : @green_tree.EventBuffer
  errors          : Array[Diagnostic]
  mut error_count : Int
  mut open_nodes  : Int
}

///|
pub fn[T, K] ParserContext::new(
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

///|
/// Return the current token without consuming it.
pub fn[T, K] ParserContext::peek(self : ParserContext[T, K]) -> T {
  if self.position < self.tokens.length() {
    self.tokens[self.position].token
  } else {
    self.spec.eof_token
  }
}

///|
/// Return current token with position info.
pub fn[T, K] ParserContext::peek_info(
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
pub fn[T, K] ParserContext::at(self : ParserContext[T, K], token : T) -> Bool {
  (self.spec.tokens_equal)(self.peek(), token)
}

///|
/// Return true if at end of input.
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
fn[T, K] ParserContext::emit_whitespace_before(
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
pub fn[T, K] ParserContext::emit_token(
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
  msg  : String,
) -> Unit {
  let info = self.peek_info()
  self.errors.push({ message: msg, start: info.start, end: info.end })
  self.error_count = self.error_count + 1
}

///|
/// Consume the current token and emit it as an error token (for error recovery).
pub fn[T, K] ParserContext::bump_error(self : ParserContext[T, K]) -> Unit {
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
test "at matches current token" {
  let (spec, tokens) = make_test_fixtures()
  let ctx = ParserContext::new(tokens, "ab", spec)
  inspect(ctx.at("a"), content="true")
  inspect(ctx.at("b"), content="false")
}
