///|
const MAX_ERRORS : Int = 50

///|
/// Convert SyntaxKind to RawKind for green-tree events.
fn raw(kind : @syntax.SyntaxKind) -> @seam.RawKind {
  kind.to_raw()
}

///|
/// Create a ReuseCursor from an old green tree and a pre-tokenized new stream.
/// Bridges the @parse API to @core.ReuseCursor for callers (e.g. incremental).
pub fn make_reuse_cursor(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  tokens : Array[@token.TokenInfo],
) -> @core.ReuseCursor[@token.Token, @syntax.SyntaxKind] {
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    lambda_spec,
  )
}

///|
/// Core parse-and-build with optional reuse cursor. Shared by the incremental
/// entry points. Returns (tree, errors, reuse_count).
fn run_parse_incremental(
  tokens : Array[@token.TokenInfo],
  source : String,
  interner : @seam.Interner?,
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
    select_build_tree(ctx.events.to_events(), interner),
    ctx.errors,
    ctx.reuse_count,
  )
}

///|
fn select_build_tree(
  events : Array[@seam.ParseEvent],
  interner : @seam.Interner?,
) -> @seam.CstNode {
  let ws = raw(@syntax.WhitespaceToken)
  match interner {
    Some(i) =>
      @seam.build_tree_interned(
        events,
        raw(@syntax.SourceFile),
        i,
        trivia_kind=Some(ws),
      )
    None =>
      @seam.build_tree(events, raw(@syntax.SourceFile), trivia_kind=Some(ws))
  }
}

///|
/// Strict: raises ParseError on first syntax error (backward compat).
/// The ParseError token field comes directly from the diagnostic's got_token.
/// Prefer parse_cst_recover for new code; this function is retained for
/// callers that depend on the raising contract.
pub fn parse_cst(source : String) -> @seam.CstNode raise {
  let (cst, errors) = parse_cst_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, diag.got_token)
  }
  cst
}

///|
/// Core parse-and-build sequence shared by all three public entry points.
/// Accepts a raw @token.TokenInfo array and builds indexed accessors to avoid
/// allocating a wrapper Array[@core.TokenInfo].
fn run_parse(
  tokens : Array[@token.TokenInfo],
  source : String,
  interner : @seam.Interner?,
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
  (select_build_tree(ctx.events.to_events(), interner), ctx.errors)
}

///|
/// Recovering: returns tree with ErrorNodes + diagnostic list.
/// Only raises for TokenizationError (unrecoverable).
pub fn parse_cst_recover(
  source : String,
  interner? : @seam.Interner? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @lexer.TokenizationError {
  let tokens = @lexer.tokenize(source)
  run_parse(tokens, source, interner)
}

///|
/// Parse with reuse cursor for incremental parsing with subtree reuse.
///
/// Uses the supplied token stream directly — never re-tokenizes from source.
/// Note: this function does not accept an Interner. For incremental use with
/// token deduplication, prefer parse_cst_recover_with_tokens which supports
/// the interner? parameter.
pub fn parse_cst_with_cursor(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind],
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  run_parse_incremental(tokens, source, None, Some(cursor), prev_diagnostics)
}

///|
/// Parse with pre-tokenized input and optional reuse cursor.
///
/// Uses the supplied token stream directly — never re-tokenizes from source,
/// so temporarily invalid source text does not cause a hard crash.
///
/// `prev_diagnostics` is only forwarded to the context when `cursor` is also
/// `Some`. Passing `prev_diagnostics=Some(diags)` with `cursor=None` has no
/// effect; the diagnostics are not replayed.
pub fn parse_cst_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
  interner? : @seam.Interner? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  run_parse_incremental(tokens, source, interner, cursor, prev_diagnostics)
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
    @token.Plus | @token.Minus =>
      ctx.wrap_at(mark, @syntax.BinaryExpr, fn() {
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
      })
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
    | @token.Lambda =>
      ctx.wrap_at(mark, @syntax.AppExpr, fn() {
        while ctx.error_count < MAX_ERRORS {
          match ctx.peek() {
            @token.LeftParen
            | @token.Identifier(_)
            | @token.Integer(_)
            | @token.Lambda => parse_atom(ctx)
            _ => break
          }
        }
      })
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
    @token.Integer(_) =>
      ctx.node(@syntax.IntLiteral, fn() { ctx.emit_token(@syntax.IntToken) })
    @token.Identifier(_) =>
      ctx.node(@syntax.VarRef, fn() { ctx.emit_token(@syntax.IdentToken) })
    @token.Lambda =>
      ctx.node(@syntax.LambdaExpr, () => {
        ctx.emit_token(@syntax.LambdaToken)
        match ctx.peek() {
          @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
          _ => {
            ctx.error("Expected parameter after λ")
            ctx.emit_error_placeholder()
          }
        }
        lambda_expect(ctx, @token.Dot, @syntax.DotToken)
        parse_expression(ctx)
      })
    @token.If =>
      ctx.node(@syntax.IfExpr, fn() {
        ctx.emit_token(@syntax.IfKeyword)
        parse_expression(ctx)
        lambda_expect(ctx, @token.Then, @syntax.ThenKeyword)
        parse_expression(ctx)
        lambda_expect(ctx, @token.Else, @syntax.ElseKeyword)
        parse_expression(ctx)
      })
    @token.LeftParen =>
      ctx.node(@syntax.ParenExpr, fn() {
        ctx.emit_token(@syntax.LeftParenToken)
        parse_expression(ctx)
        lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken)
      })
    _ => {
      // Error recovery — never reuse error nodes; keep raw start/finish_node.
      ctx.error("Unexpected token")
      if at_stop_token(ctx) {
        ctx.start_node(@syntax.ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        ctx.start_node(@syntax.ErrorNode)
        ctx.bump_error()
        ctx.finish_node()
      }
    }
  }
}
