///|
let max_errors : Int = 50

///|
/// Convert SyntaxKind to RawKind for green-tree events.
fn raw(kind : @syntax.SyntaxKind) -> @green_tree.RawKind {
  kind.to_raw()
}

///|
/// Bridge: convert @syntax.GreenNode to @green_tree.GreenNode.
/// Used only in GreenParser::try_reuse to bridge the Task-7 shim.
fn syntax_node_to_gt(node : @syntax.GreenNode) -> @green_tree.GreenNode {
  let children = node.children.map(syntax_elem_to_gt)
  @green_tree.GreenNode::new(raw(node.kind), children)
}

///|
fn syntax_elem_to_gt(elem : @syntax.GreenElement) -> @green_tree.GreenElement {
  match elem {
    @syntax.GreenElement::Token(t) =>
      @green_tree.GreenElement::Token(
        @green_tree.GreenToken::new(raw(t.kind), t.text),
      )
    @syntax.GreenElement::Node(n) =>
      @green_tree.GreenElement::Node(syntax_node_to_gt(n))
  }
}

///|
/// Bridge: convert @green_tree.GreenNode to @syntax.GreenNode.
/// Temporary shim until Task 7 migrates reuse_cursor.mbt to RawKind.
fn gt_node_to_syntax(node : @green_tree.GreenNode) -> @syntax.GreenNode {
  let kind = @syntax.SyntaxKind::from_raw(node.kind)
  let children = node.children.map(gt_elem_to_syntax)
  @syntax.GreenNode::new(kind, children)
}

///|
fn gt_elem_to_syntax(elem : @green_tree.GreenElement) -> @syntax.GreenElement {
  match elem {
    @green_tree.GreenElement::Token(t) =>
      @syntax.GreenElement::Token(
        @syntax.GreenToken::new(@syntax.SyntaxKind::from_raw(t.kind), t.text),
      )
    @green_tree.GreenElement::Node(n) =>
      @syntax.GreenElement::Node(gt_node_to_syntax(n))
  }
}

///|
/// Create a ReuseCursor from a @green_tree.GreenNode.
/// Temporary bridge until Task 7 migrates reuse_cursor.mbt to RawKind.
pub fn make_reuse_cursor(
  old_tree : @green_tree.GreenNode,
  damaged_range : @range.Range,
  tokens : Array[@token.TokenInfo],
) -> ReuseCursor {
  let syntax_tree = gt_node_to_syntax(old_tree)
  ReuseCursor::new(syntax_tree, damaged_range, tokens)
}

///|
priv struct GreenParser {
  tokens : Array[@token.TokenInfo]
  source : String
  mut position : Int
  mut last_end : Int // Track last token end to emit whitespace
  events : @green_tree.EventBuffer
  errors : Array[ParseDiagnostic]
  mut error_count : Int
  cursor : ReuseCursor? // Optional reuse cursor for incremental parsing
  mut reuse_count : Int // Count of reused nodes (for statistics)
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
) -> (@green_tree.GreenNode, Array[ParseDiagnostic]) raise @lexer.TokenizationError {
  let tokens = @lexer.tokenize(source)
  let parser = GreenParser::new(tokens, source)
  parser.parse_source_file()
  let tree = @green_tree.build_tree(
    parser.events.events,
    raw(@syntax.SourceFile),
  )
  (tree, parser.errors)
}

///|
/// Parse with reuse cursor for incremental parsing with subtree reuse.
/// Returns (green_tree, diagnostics, reuse_count).
pub fn parse_green_with_cursor(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : ReuseCursor,
) -> (@green_tree.GreenNode, Array[ParseDiagnostic], Int) {
  let parser = GreenParser::new_with_cursor(tokens, source, cursor)
  parser.parse_source_file()
  let tree = @green_tree.build_tree(
    parser.events.events,
    raw(@syntax.SourceFile),
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
) -> (@green_tree.GreenNode, Array[ParseDiagnostic], Int) {
  let parser = match cursor {
    Some(c) => GreenParser::new_with_cursor(tokens, source, c)
    None => GreenParser::new(tokens, source)
  }
  parser.parse_source_file()
  let tree = @green_tree.build_tree(
    parser.events.events,
    raw(@syntax.SourceFile),
  )
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
    last_end: 0,
    events: @green_tree.EventBuffer::new(),
    errors: [],
    error_count: 0,
    cursor: None,
    reuse_count: 0,
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
    last_end: 0,
    events: @green_tree.EventBuffer::new(),
    errors: [],
    error_count: 0,
    cursor: Some(cursor),
    reuse_count: 0,
  }
}

///|
fn GreenParser::start_node(
  self : GreenParser,
  kind : @syntax.SyntaxKind,
) -> Unit {
  self.events.push(@green_tree.StartNode(raw(kind)))
}

///|
fn GreenParser::finish_node(self : GreenParser) -> Unit {
  self.events.push(@green_tree.FinishNode)
}

///|
fn GreenParser::peek(self : GreenParser) -> @token.Token {
  if self.position < self.tokens.length() {
    self.tokens[self.position].token
  } else {
    @token.EOF
  }
}

///|
fn GreenParser::peek_info(self : GreenParser) -> @token.TokenInfo {
  if self.position < self.tokens.length() {
    self.tokens[self.position]
  } else {
    let end = self.source.length()
    @token.TokenInfo::new(@token.EOF, end, end)
  }
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
fn GreenParser::emit_whitespace_before(
  self : GreenParser,
  info : @token.TokenInfo,
) -> Unit {
  if info.start > self.last_end {
    let ws_text : StringView = self.source[self.last_end:info.start] catch {
        _ => ""
      }
    self.events.push(
      @green_tree.ParseEvent::Token(
        raw(@syntax.WhitespaceToken),
        ws_text.to_string(),
      ),
    )
  }
}

///|
fn GreenParser::emit_token(
  self : GreenParser,
  kind : @syntax.SyntaxKind,
) -> Unit {
  let info = self.peek_info()
  self.emit_whitespace_before(info)
  let text = self.token_text(info)
  self.events.push(@green_tree.ParseEvent::Token(raw(kind), text))
  self.last_end = info.end
  self.advance()
}

///|
/// Emit events to reconstruct a reused green node.
/// Does NOT update position/last_end - caller must do that.
fn GreenParser::emit_reused_node_events(
  self : GreenParser,
  node : @green_tree.GreenNode,
) -> Unit {
  self.events.push(@green_tree.StartNode(node.kind))
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        self.events.push(@green_tree.ParseEvent::Token(t.kind, t.text))
      @green_tree.GreenElement::Node(n) => self.emit_reused_node_events(n)
    }
  }
  self.events.push(@green_tree.FinishNode)
}

///|
/// Count non-whitespace tokens in a green node (recursive).
/// This matches how the lexer produces tokens (whitespace is skipped).
fn count_tokens_in_green(node : @green_tree.GreenNode) -> Int {
  let mut count = 0
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        // Only count non-whitespace tokens to match lexer output
        if t.kind != @syntax.WhitespaceToken.to_raw() {
          count = count + 1
        }
      @green_tree.GreenElement::Node(n) =>
        count = count + count_tokens_in_green(n)
    }
  }
  count
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
      // Get the current byte offset from the current token
      let info = self.peek_info()
      let byte_offset = info.start
      match
        cursor.try_reuse(
          @syntax.SyntaxKind::from_raw(expected_kind),
          byte_offset,
          self.position,
        ) {
        None => false
        Some(node) => {
          // Convert the @syntax.GreenNode shim result to @green_tree.GreenNode
          let gt_node = syntax_node_to_gt(node)
          // Emit whitespace before the reused node (gap between last_end and token start)
          self.emit_whitespace_before(info)
          // Set last_end to node start before emitting reused events,
          // so internal whitespace in the reused node is not double-counted
          self.last_end = info.start
          // Emit the reused node events
          self.emit_reused_node_events(gt_node)
          // Update position by non-whitespace token count
          let token_count = count_tokens_in_green(gt_node)
          self.position = self.position + token_count
          // Update last_end past the reused node
          self.last_end = info.start + node.text_len
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
/// Consume current token as an ErrorToken (emit whitespace + token).
fn GreenParser::bump_error(self : GreenParser) -> Unit {
  let info = self.peek_info()
  self.emit_whitespace_before(info)
  let text = self.token_text(info)
  self.events.push(@green_tree.ParseEvent::Token(raw(@syntax.ErrorToken), text))
  self.last_end = info.end
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
      if self.last_end < self.source.length() {
        let ws_text : StringView = self.source[self.last_end:self.source.length()] catch {
            _ => ""
          }
        self.events.push(
          @green_tree.ParseEvent::Token(
            raw(@syntax.WhitespaceToken),
            ws_text.to_string(),
          ),
        )
        self.last_end = self.source.length()
      }
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
      // Emit trailing whitespace if any
      if self.last_end < self.source.length() {
        let ws_text : StringView = self.source[self.last_end:self.source.length()] catch {
            _ => ""
          }
        self.events.push(
          @green_tree.ParseEvent::Token(
            raw(@syntax.WhitespaceToken),
            ws_text.to_string(),
          ),
        )
        self.last_end = self.source.length()
      }
    }
  }
}

///|
fn GreenParser::parse_expression(self : GreenParser) -> Unit {
  self.parse_binary_op()
}

///|
fn GreenParser::parse_binary_op(self : GreenParser) -> Unit {
  let mark = self.events.mark()
  self.parse_application()
  match self.peek() {
    @token.Plus | @token.Minus => {
      self.events.start_at(mark, raw(@syntax.BinaryExpr))
      while self.error_count < max_errors {
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
  let mark = self.events.mark()
  self.parse_atom()
  match self.peek() {
    @token.LeftParen
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda => {
      self.events.start_at(mark, raw(@syntax.AppExpr))
      while self.error_count < max_errors {
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
  if self.error_count >= max_errors {
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
