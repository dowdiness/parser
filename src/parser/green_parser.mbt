///|
const MAX_ERRORS : Int = 50

///|
/// Convert SyntaxKind to RawKind for green-tree events.
fn raw(kind : @syntax.SyntaxKind) -> @green_tree.RawKind {
  kind.to_raw()
}

///|
/// Create a ReuseCursor from a @green_tree.GreenNode.
pub fn make_reuse_cursor(
  old_tree : @green_tree.GreenNode,
  damaged_range : @range.Range,
  tokens : Array[@token.TokenInfo],
) -> ReuseCursor {
  ReuseCursor::new(old_tree, damaged_range, tokens)
}

///|
priv struct GreenParser {
  tokens : Array[@token.TokenInfo]
  source : String
  mut position : Int
  events : @green_tree.EventBuffer
  errors : Array[ParseDiagnostic]
  mut error_count : Int
  cursor : ReuseCursor? // Optional reuse cursor for incremental parsing
  mut reuse_count : Int // Count of reused nodes (for statistics)
  mut open_nodes : Int // Number of currently open StartNode events
}

///|
fn select_build_tree(
  events : Array[@green_tree.ParseEvent],
  interner : @green_tree.Interner?,
) -> @green_tree.GreenNode {
  let ws = raw(@syntax.WhitespaceToken)
  match interner {
    Some(i) =>
      @green_tree.build_tree_interned(
        events,
        raw(@syntax.SourceFile),
        i,
        trivia_kind=Some(ws),
      )
    None =>
      @green_tree.build_tree(
        events,
        raw(@syntax.SourceFile),
        trivia_kind=Some(ws),
      )
  }
}

///|
/// Strict: raises ParseError on first syntax error (backward compat)
pub fn parse_green(source : String) -> @green_tree.GreenNode raise {
  let (green, errors) = parse_green_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, diag.token)
  }
  green
}

///|
/// Recovering: returns tree with ErrorNodes + diagnostic list.
/// Only raises for TokenizationError (unrecoverable).
pub fn parse_green_recover(
  source : String,
  interner? : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[ParseDiagnostic]) raise @lexer.TokenizationError {
  let tokens = @lexer.tokenize(source)
  let parser = GreenParser::new(tokens, source)
  parser.parse_source_file()
  parser.assert_event_balance()
  let tree = select_build_tree(parser.events.events, interner)
  (tree, parser.errors)
}

///|
/// Parse with reuse cursor for incremental parsing with subtree reuse.
/// Returns (green_tree, diagnostics, reuse_count).
///
/// Note: this function does not accept an Interner. For incremental use with
/// token deduplication, prefer parse_green_recover_with_tokens which supports
/// the interner? parameter.
pub fn parse_green_with_cursor(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : ReuseCursor,
) -> (@green_tree.GreenNode, Array[ParseDiagnostic], Int) {
  let parser = GreenParser::new_with_cursor(tokens, source, cursor)
  parser.parse_source_file()
  parser.assert_event_balance()
  let tree = @green_tree.build_tree(
    parser.events.events,
    raw(@syntax.SourceFile),
    trivia_kind=Some(raw(@syntax.WhitespaceToken)),
  )
  (tree, parser.errors, parser.reuse_count)
}

///|
/// Parse with pre-tokenized input and optional reuse cursor.
/// Returns (green_tree, diagnostics, reuse_count).
pub fn parse_green_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : ReuseCursor?,
  interner? : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[ParseDiagnostic], Int) {
  let parser = match cursor {
    Some(c) => GreenParser::new_with_cursor(tokens, source, c)
    None => GreenParser::new(tokens, source)
  }
  parser.parse_source_file()
  parser.assert_event_balance()
  let tree = select_build_tree(parser.events.events, interner)
  (tree, parser.errors, parser.reuse_count)
}

///|
fn GreenParser::new(
  tokens : Array[@token.TokenInfo],
  source : String,
) -> GreenParser {
  {
    tokens,
    source,
    position: 0,
    events: @green_tree.EventBuffer::new(),
    errors: [],
    error_count: 0,
    cursor: None,
    reuse_count: 0,
    open_nodes: 0,
  }
}

///|
fn GreenParser::new_with_cursor(
  tokens : Array[@token.TokenInfo],
  source : String,
  cursor : ReuseCursor,
) -> GreenParser {
  {
    tokens,
    source,
    position: 0,
    events: @green_tree.EventBuffer::new(),
    errors: [],
    error_count: 0,
    cursor: Some(cursor),
    reuse_count: 0,
    open_nodes: 0,
  }
}

///|
fn GreenParser::start_node(
  self : GreenParser,
  kind : @syntax.SyntaxKind,
) -> Unit {
  // Producer-side invariant tracking for StartNode/FinishNode balance.
  self.open_nodes = self.open_nodes + 1
  self.events.push(@green_tree.StartNode(raw(kind)))
}

///|
fn GreenParser::mark_node(self : GreenParser) -> Int {
  // mark() reserves a Tombstone that may later be claimed by start_marked_node.
  self.events.mark()
}

///|
fn GreenParser::start_marked_node(
  self : GreenParser,
  mark : Int,
  kind : @syntax.SyntaxKind,
) -> Unit {
  // Marked starts must also participate in open_nodes accounting.
  self.events.start_at(mark, raw(kind))
  self.open_nodes = self.open_nodes + 1
}

///|
fn GreenParser::finish_node(self : GreenParser) -> Unit {
  if self.open_nodes <= 0 {
    abort("GreenParser::finish_node: FinishNode without matching StartNode")
  }
  self.open_nodes = self.open_nodes - 1
  self.events.push(@green_tree.FinishNode)
}

///|
fn GreenParser::assert_event_balance(self : GreenParser) -> Unit {
  // SourceFile is an implicit root passed to @green_tree.build_tree(root_kind).
  // It is not emitted as StartNode/FinishNode events, so a balanced stream
  // must end with open_nodes == 0.
  if self.open_nodes != 0 {
    abort(
      "GreenParser: unbalanced parse events, open_nodes=" +
      self.open_nodes.to_string(),
    )
  }
}

///|
/// Return the next non-Whitespace token, skipping any Whitespace entries.
fn GreenParser::peek(self : GreenParser) -> @token.Token {
  let mut pos = self.position
  while pos < self.tokens.length() {
    match self.tokens[pos].token {
      @token.Whitespace => pos = pos + 1
      token => return token
    }
  }
  @token.EOF
}

///|
/// Return the TokenInfo for the next non-Whitespace token.
fn GreenParser::peek_info(self : GreenParser) -> @token.TokenInfo {
  let mut pos = self.position
  while pos < self.tokens.length() {
    let info = self.tokens[pos]
    match info.token {
      @token.Whitespace => pos = pos + 1
      _ => return info
    }
  }
  let end = self.source.length()
  @token.TokenInfo::new(@token.EOF, end, end)
}

///|
/// Return the array index of the next non-Whitespace token at or after start_pos.
fn GreenParser::find_next_syntactic(self : GreenParser, start_pos : Int) -> Int {
  let mut pos = start_pos
  while pos < self.tokens.length() {
    match self.tokens[pos].token {
      @token.Whitespace => pos = pos + 1
      _ => return pos
    }
  }
  self.tokens.length()
}

///|
fn GreenParser::advance(self : GreenParser) -> Unit {
  self.position = self.position + 1
}

///|
fn GreenParser::token_text(
  self : GreenParser,
  info : @token.TokenInfo,
) -> String {
  let slice : StringView = self.source[info.start:info.end] catch { _ => "" }
  slice.to_string()
}

///|
/// Emit all consecutive Whitespace tokens at current position to the
/// event stream, advancing position past each one.
fn GreenParser::flush_trivia(self : GreenParser) -> Unit {
  while self.position < self.tokens.length() {
    let info = self.tokens[self.position]
    match info.token {
      @token.Whitespace => {
        let text = self.token_text(info)
        self.events.push(
          @green_tree.ParseEvent::Token(raw(@syntax.WhitespaceToken), text),
        )
        self.position = self.position + 1
      }
      _ => break
    }
  }
}

///|
fn GreenParser::emit_token(
  self : GreenParser,
  kind : @syntax.SyntaxKind,
) -> Unit {
  self.flush_trivia()
  let info = self.peek_info()
  let text = self.token_text(info)
  self.events.push(@green_tree.ParseEvent::Token(raw(kind), text))
  self.advance()
}

///|
/// Emit events to reconstruct a reused green node.
/// Does NOT update position — caller must advance position after calling this.
fn GreenParser::emit_reused_node_events(
  self : GreenParser,
  node : @green_tree.GreenNode,
) -> Unit {
  // Re-emitting a reused subtree is logically equivalent to emitting a fresh
  // balanced StartNode ... FinishNode region.
  self.open_nodes = self.open_nodes + 1
  self.events.push(@green_tree.StartNode(node.kind))
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        self.events.push(@green_tree.ParseEvent::Token(t.kind, t.text))
      @green_tree.GreenElement::Node(n) => self.emit_reused_node_events(n)
    }
  }
  self.open_nodes = self.open_nodes - 1
  self.events.push(@green_tree.FinishNode)
}

///|
/// Try to reuse a node at current position for given expected kind
fn GreenParser::try_reuse(
  self : GreenParser,
  expected_kind : @green_tree.RawKind,
) -> Bool {
  match self.cursor {
    None => false
    Some(cursor) => {
      // Fast path: skip all work if reuse is globally disabled
      if cursor.is_reuse_disabled() {
        return false
      }
      // Get the current byte offset from the next syntactic token (skip whitespace)
      let info = self.peek_info()
      let byte_offset = info.start
      // token_pos must point to the first syntactic (non-whitespace) token so
      // leading_token_matches and trailing_context_matches see real tokens.
      let token_pos = self.find_next_syntactic(self.position)
      match cursor.try_reuse(expected_kind, byte_offset, token_pos) {
        None => false
        Some(node) => {
          // Flush any leading trivia (whitespace before the reused node)
          self.flush_trivia()
          // Emit the reused node events
          self.emit_reused_node_events(node)
          // Advance position past ALL tokens (whitespace + syntactic) that
          // fall within the reused node's byte span [byte_offset, node_end).
          let node_end = byte_offset + node.text_len
          while self.position < self.tokens.length() &&
                self.tokens[self.position].start < node_end {
            self.position = self.position + 1
          }
          self.reuse_count = self.reuse_count + 1
          // Advance cursor past the reused node
          cursor.advance_past(node)
          true
        }
      }
    }
  }
}

///|
/// Record a diagnostic and increment error count.
fn GreenParser::error(
  self : GreenParser,
  msg : String,
  token : @token.Token,
  start : Int,
  end : Int,
) -> Unit {
  self.errors.push({ message: msg, token, start, end })
  self.error_count = self.error_count + 1
}

///|
/// Consume current token as an ErrorToken (flush trivia then emit token).
fn GreenParser::bump_error(self : GreenParser) -> Unit {
  self.flush_trivia()
  let info = self.peek_info()
  let text = self.token_text(info)
  self.events.push(@green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), text))
  self.advance()
}

///|
/// Check if current token is a sync/stop point.
fn GreenParser::at_stop_token(self : GreenParser) -> Bool {
  match self.peek() {
    @token.RightParen | @token.Then | @token.Else | @token.EOF => true
    _ => false
  }
}

///|
fn GreenParser::expect(
  self : GreenParser,
  expected : @token.Token,
  kind : @syntax.SyntaxKind,
) -> Unit {
  let current = self.peek()
  match (current, expected) {
    (a, b) if a == b => self.emit_token(kind)
    _ => {
      let info = self.peek_info()
      self.error(
        "Expected " + @token.print_token(expected),
        current,
        info.start,
        info.end,
      )
      // Emit zero-width ErrorToken — do NOT consume current token
      self.events.push(
        @green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), ""),
      )
    }
  }
}

///|
fn GreenParser::parse_source_file(self : GreenParser) -> Unit {
  self.parse_expression()
  match self.peek() {
    @token.EOF =>
      // Flush any trailing whitespace tokens before EOF
      self.flush_trivia()
    _ => {
      // Wrap all remaining tokens (until EOF) in a single ErrorNode
      let info = self.peek_info()
      self.error(
        "Unexpected tokens after expression",
        info.token,
        info.start,
        info.end,
      )
      self.start_node(@syntax.ErrorNode)
      while self.peek() != @token.EOF {
        self.bump_error()
      }
      self.finish_node()
      // Flush any trailing whitespace tokens after the ErrorNode
      self.flush_trivia()
    }
  }
}

///|
fn GreenParser::parse_expression(self : GreenParser) -> Unit {
  self.parse_binary_op()
}

///|
fn GreenParser::parse_binary_op(self : GreenParser) -> Unit {
  let mark = self.mark_node()
  self.parse_application()
  match self.peek() {
    @token.Plus | @token.Minus => {
      self.start_marked_node(mark, @syntax.BinaryExpr)
      while self.error_count < MAX_ERRORS {
        match self.peek() {
          @token.Plus => {
            self.emit_token(@syntax.PlusToken)
            self.parse_application()
          }
          @token.Minus => {
            self.emit_token(@syntax.MinusToken)
            self.parse_application()
          }
          _ => break
        }
      }
      self.finish_node()
    }
    _ => ()
  }
}

///|
fn GreenParser::parse_application(self : GreenParser) -> Unit {
  let mark = self.mark_node()
  self.parse_atom()
  match self.peek() {
    @token.LeftParen
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda => {
      self.start_marked_node(mark, @syntax.AppExpr)
      while self.error_count < MAX_ERRORS {
        match self.peek() {
          @token.LeftParen
          | @token.Identifier(_)
          | @token.Integer(_)
          | @token.Lambda => self.parse_atom()
          _ => break
        }
      }
      self.finish_node()
    }
    _ => ()
  }
}

///|
fn GreenParser::parse_atom(self : GreenParser) -> Unit {
  if self.error_count >= MAX_ERRORS {
    return
  }

  // Try reuse for each atom kind before parsing fresh
  if self.try_reuse(raw(@syntax.IntLiteral)) {
    return
  }
  if self.try_reuse(raw(@syntax.VarRef)) {
    return
  }
  if self.try_reuse(raw(@syntax.LambdaExpr)) {
    return
  }
  if self.try_reuse(raw(@syntax.IfExpr)) {
    return
  }
  if self.try_reuse(raw(@syntax.ParenExpr)) {
    return
  }

  // No reuse possible, parse fresh
  match self.peek() {
    @token.Integer(_) => {
      self.start_node(@syntax.IntLiteral)
      self.emit_token(@syntax.IntToken)
      self.finish_node()
    }
    @token.Identifier(_) => {
      self.start_node(@syntax.VarRef)
      self.emit_token(@syntax.IdentToken)
      self.finish_node()
    }
    @token.Lambda => {
      self.start_node(@syntax.LambdaExpr)
      self.emit_token(@syntax.LambdaToken)
      match self.peek() {
        @token.Identifier(_) => self.emit_token(@syntax.IdentToken)
        token => {
          let info = self.peek_info()
          self.error("Expected parameter after λ", token, info.start, info.end)
          // Emit zero-width ErrorToken for missing identifier
          self.events.push(
            @green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), ""),
          )
        }
      }
      self.expect(@token.Dot, @syntax.DotToken)
      self.parse_expression()
      self.finish_node()
    }
    @token.If => {
      self.start_node(@syntax.IfExpr)
      self.emit_token(@syntax.IfKeyword)
      self.parse_expression()
      self.expect(@token.Then, @syntax.ThenKeyword)
      self.parse_expression()
      self.expect(@token.Else, @syntax.ElseKeyword)
      self.parse_expression()
      self.finish_node()
    }
    @token.LeftParen => {
      self.start_node(@syntax.ParenExpr)
      self.emit_token(@syntax.LeftParenToken)
      self.parse_expression()
      self.expect(@token.RightParen, @syntax.RightParenToken)
      self.finish_node()
    }
    token => {
      let info = self.peek_info()
      self.error("Unexpected token", token, info.start, info.end)
      if self.at_stop_token() {
        // Stop token: emit zero-width ErrorNode (don't consume)
        self.start_node(@syntax.ErrorNode)
        self.events.push(
          @green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), ""),
        )
        self.finish_node()
      } else {
        // Wrap current token in ErrorNode (consume it)
        self.start_node(@syntax.ErrorNode)
        self.bump_error()
        self.finish_node()
      }
    }
  }
}
