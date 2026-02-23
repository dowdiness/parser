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
/// Strict: raises ParseError on first syntax error (backward compat).
/// The ParseError token field is recovered from the diagnostic's byte offset
/// via token_at_offset — it reflects the actual offending token, not EOF.
/// Prefer parse_green_recover for new code; this function is retained for
/// callers that depend on the raising contract.
pub fn parse_green(source : String) -> @green_tree.GreenNode raise {
  let (green, errors) = parse_green_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, token_at_offset(source, diag.start))
  }
  green
}

///|
/// Return the token at the given byte offset, or EOF if not found.
/// Only called on the error path; double tokenization cost is acceptable.
/// Assumes that diagnostic byte offsets align with token start positions as
/// recorded by @lexer.tokenize. Returns EOF if the offset is past end-of-input
/// or falls between tokens — both are safe fallbacks for the ParseError caller.
fn token_at_offset(source : String, offset : Int) -> @token.Token {
  let tokens = @lexer.tokenize(source) catch {
    @lexer.TokenizationError(_) => return @token.EOF
  }
  for ti in tokens {
    if ti.start == offset {
      return ti.token
    }
  }
  @token.EOF
}

///|
/// Core parse-and-build sequence shared by all three public entry points.
/// Accepts pre-converted core tokens, source, and optional interner.
/// Aborts if the grammar leaves unclosed nodes (programming error).
fn run_parse(
  core_tokens : Array[@core.TokenInfo[@token.Token]],
  source : String,
  interner : @green_tree.Interner?,
) -> (@green_tree.GreenNode, Array[@core.Diagnostic]) {
  let ctx = @core.ParserContext::new(core_tokens, source, lambda_spec)
  parse_lambda_root(ctx)
  ctx.flush_trivia()
  if ctx.open_nodes != 0 {
    abort(
      "run_parse: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
  (select_build_tree(ctx.events.events, interner), ctx.errors)
}

///|
/// Recovering: returns tree with ErrorNodes + diagnostic list.
/// Only raises for TokenizationError (unrecoverable).
pub fn parse_green_recover(
  source : String,
  interner? : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[@core.Diagnostic]) raise @lexer.TokenizationError {
  let raw_tokens = @lexer.tokenize(source)
  let tokens = raw_tokens.map(fn(ti) {
    @core.TokenInfo::new(ti.token, ti.start, ti.end)
  })
  run_parse(tokens, source, interner)
}

///|
/// Parse with reuse cursor for incremental parsing with subtree reuse.
///
/// Uses the supplied token stream directly — never re-tokenizes from source.
/// DEFERRED: cursor is ignored and reuse_count is always 0 until cursor
/// support is restored.
///
/// Note: this function does not accept an Interner. For incremental use with
/// token deduplication, prefer parse_green_recover_with_tokens which supports
/// the interner? parameter.
pub fn parse_green_with_cursor(
  source : String,
  tokens : Array[@token.TokenInfo],
  _cursor : ReuseCursor,
) -> (@green_tree.GreenNode, Array[@core.Diagnostic], Int) {
  let core_tokens = tokens.map(fn(ti) {
    @core.TokenInfo::new(ti.token, ti.start, ti.end)
  })
  let (tree, errors) = run_parse(core_tokens, source, None)
  (tree, errors, 0)
}

///|
/// Parse with pre-tokenized input and optional reuse cursor.
///
/// Uses the supplied token stream directly — never re-tokenizes from source,
/// so temporarily invalid source text does not cause a hard crash.
/// DEFERRED: cursor is ignored and reuse_count is always 0 until cursor
/// support is restored.
pub fn parse_green_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo],
  _cursor : ReuseCursor?,
  interner? : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[@core.Diagnostic], Int) {
  let core_tokens = tokens.map(fn(ti) {
    @core.TokenInfo::new(ti.token, ti.start, ti.end)
  })
  let (tree, errors) = run_parse(core_tokens, source, interner)
  (tree, errors, 0)
}

// ─── Grammar helpers ─────────────────────────────────────────────────────────

///|
fn at_stop_token(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  match ctx.peek() {
    @token.RightParen | @token.Then | @token.Else | @token.EOF => true
    _ => false
  }
}

///|
fn lambda_expect(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  expected : @token.Token,
  kind : @syntax.SyntaxKind,
) -> Unit {
  let current = ctx.peek()
  match (current, expected) {
    (a, b) if a == b => ctx.emit_token(kind)
    _ => {
      ctx.error("Expected " + @token.print_token(expected))
      // Emit zero-width ErrorToken — do NOT consume current token
      ctx.emit_error_placeholder()
    }
  }
}

// ─── Grammar (entry point + rules) ───────────────────────────────────────────

///|
/// Entry point passed to @core.ParserContext. Parses one expression then
/// wraps any trailing junk in an ErrorNode.
fn parse_lambda_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  parse_expression(ctx)
  match ctx.peek() {
    @token.EOF =>
      // Flush any trailing whitespace tokens before EOF
      ctx.flush_trivia()
    _ => {
      // Wrap all remaining tokens (until EOF) in a single ErrorNode
      ctx.error("Unexpected tokens after expression")
      ctx.start_node(@syntax.ErrorNode)
      while ctx.peek() != @token.EOF {
        ctx.bump_error()
      }
      ctx.finish_node()
      // Flush any trailing whitespace tokens after the ErrorNode
      ctx.flush_trivia()
    }
  }
}

///|
fn parse_expression(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  parse_binary_op(ctx)
}

///|
fn parse_binary_op(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  parse_application(ctx)
  match ctx.peek() {
    @token.Plus | @token.Minus => {
      ctx.start_at(mark, @syntax.BinaryExpr)
      while ctx.error_count < MAX_ERRORS {
        match ctx.peek() {
          @token.Plus => {
            ctx.emit_token(@syntax.PlusToken)
            parse_application(ctx)
          }
          @token.Minus => {
            ctx.emit_token(@syntax.MinusToken)
            parse_application(ctx)
          }
          _ => break
        }
      }
      ctx.finish_node()
    }
    _ => ()
  }
}

///|
fn parse_application(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  parse_atom(ctx)
  match ctx.peek() {
    @token.LeftParen
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda => {
      ctx.start_at(mark, @syntax.AppExpr)
      while ctx.error_count < MAX_ERRORS {
        match ctx.peek() {
          @token.LeftParen
          | @token.Identifier(_)
          | @token.Integer(_)
          | @token.Lambda => parse_atom(ctx)
          _ => break
        }
      }
      ctx.finish_node()
    }
    _ => ()
  }
}

///|
fn parse_atom(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  if ctx.error_count >= MAX_ERRORS {
    return
  }
  match ctx.peek() {
    @token.Integer(_) => {
      ctx.start_node(@syntax.IntLiteral)
      ctx.emit_token(@syntax.IntToken)
      ctx.finish_node()
    }
    @token.Identifier(_) => {
      ctx.start_node(@syntax.VarRef)
      ctx.emit_token(@syntax.IdentToken)
      ctx.finish_node()
    }
    @token.Lambda => {
      ctx.start_node(@syntax.LambdaExpr)
      ctx.emit_token(@syntax.LambdaToken)
      match ctx.peek() {
        @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
        _ => {
          ctx.error("Expected parameter after λ")
          // Emit zero-width ErrorToken for missing identifier
          ctx.emit_error_placeholder()
        }
      }
      lambda_expect(ctx, @token.Dot, @syntax.DotToken)
      parse_expression(ctx)
      ctx.finish_node()
    }
    @token.If => {
      ctx.start_node(@syntax.IfExpr)
      ctx.emit_token(@syntax.IfKeyword)
      parse_expression(ctx)
      lambda_expect(ctx, @token.Then, @syntax.ThenKeyword)
      parse_expression(ctx)
      lambda_expect(ctx, @token.Else, @syntax.ElseKeyword)
      parse_expression(ctx)
      ctx.finish_node()
    }
    @token.LeftParen => {
      ctx.start_node(@syntax.ParenExpr)
      ctx.emit_token(@syntax.LeftParenToken)
      parse_expression(ctx)
      lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken)
      ctx.finish_node()
    }
    _ => {
      ctx.error("Unexpected token")
      if at_stop_token(ctx) {
        // Stop token: emit zero-width ErrorNode (don't consume)
        ctx.start_node(@syntax.ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        // Wrap current token in ErrorNode (consume it)
        ctx.start_node(@syntax.ErrorNode)
        ctx.bump_error()
        ctx.finish_node()
      }
    }
  }
}
