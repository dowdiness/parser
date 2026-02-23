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
/// The ParseError token field comes directly from the diagnostic's got_token.
/// Prefer parse_green_recover for new code; this function is retained for
/// callers that depend on the raising contract.
pub fn parse_green(source : String) -> @green_tree.GreenNode raise {
  let (green, errors) = parse_green_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, diag.got_token)
  }
  green
}

///|
/// Core parse-and-build sequence shared by all three public entry points.
/// Accepts a raw @token.TokenInfo array and builds indexed accessors to avoid
/// allocating a wrapper Array[@core.TokenInfo].
fn run_parse(
  tokens : Array[@token.TokenInfo],
  source : String,
  interner : @green_tree.Interner?,
) -> (@green_tree.GreenNode, Array[@core.Diagnostic[@token.Token]]) {
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
  (select_build_tree(ctx.events.events, interner), ctx.errors)
}

///|
/// Recovering: returns tree with ErrorNodes + diagnostic list.
/// Only raises for TokenizationError (unrecoverable).
pub fn parse_green_recover(
  source : String,
  interner? : @green_tree.Interner? = None,
) -> (@green_tree.GreenNode, Array[@core.Diagnostic[@token.Token]]) raise @lexer.TokenizationError {
  let tokens = @lexer.tokenize(source)
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
) -> (@green_tree.GreenNode, Array[@core.Diagnostic[@token.Token]], Int) {
  let (tree, errors) = run_parse(tokens, source, None)
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
) -> (@green_tree.GreenNode, Array[@core.Diagnostic[@token.Token]], Int) {
  let (tree, errors) = run_parse(tokens, source, interner)
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
