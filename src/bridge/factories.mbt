// Bridge factories — build IncrementalParser or ParserDb from a Grammar.
//
// These encapsulate all infrastructure wiring: TokenBuffer lifecycle,
// ReuseCursor construction, parse_tokens_indexed calls, diagnostic
// formatting, lex error handling. The grammar author provides only what
// varies (spec, tokenize, to_ast); the factories handle the rest.
//
// Lex error strategy: parse 0 tokens → error CST → to_ast produces the
// error AST. The lex error message goes into diagnostics, not the AST.
//
// IncrementalLanguage[Ast] and Language[Ast] are constructed internally
// for type erasure — grammar authors never see them.

///|
/// Parse 0 tokens to produce an error CST, then run to_ast.
/// Derives on_lex_error from the grammar's existing to_ast callback.
fn[T, K, Ast] derive_lex_error_ast(grammar : Grammar[T, K, Ast]) -> Ast {
  let spec = grammar.spec
  let (cst, _, _) = @core.parse_tokens_indexed(
    "",
    0,
    fn(_) { spec.eof_token },
    fn(_) { 0 },
    fn(_) { 0 },
    spec,
  )
  (grammar.to_ast)(@seam.SyntaxNode::from_cst(cst))
}

///|
/// Create an IncrementalParser from a Grammar.
///
/// Each call creates fresh internal state (TokenBuffer, diagnostics).
/// Safe to call multiple times — no shared mutable state between parsers.
pub fn[T, K, Ast] new_incremental_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @incremental.IncrementalParser[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let to_ast = grammar.to_ast
  let token_buf : Ref[@core.TokenBuffer[T]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[T]]] = Ref::new([])
  let lang = @incremental.IncrementalLanguage::new(
    full_parse=(source, interner, node_interner) => {
      try {
        let buffer = @core.TokenBuffer::new(
          source,
          tokenize_fn=tokenize,
          eof_token=spec.eof_token,
        )
        token_buf.val = Some(buffer)
        let tokens = buffer.get_tokens()
        let (cst, diagnostics, _) = @core.parse_tokens_indexed(
          source,
          tokens.length(),
          fn(i) { tokens[i].token },
          fn(i) { tokens[i].start },
          fn(i) { tokens[i].end },
          spec,
          interner=Some(interner),
          node_interner=Some(node_interner),
        )
        last_diags.val = diagnostics
        let syntax = @seam.SyntaxNode::from_cst(cst)
        @incremental.ParseOutcome::Tree(syntax, 0)
      } catch {
        @core.LexError(msg) => {
          token_buf.val = None
          last_diags.val = []
          @incremental.ParseOutcome::LexError("Tokenization error: " + msg)
        }
      }
    },
    incremental_parse=(source, old_syntax, edit, interner, node_interner) => {
      let tokens = match token_buf.val {
        Some(buffer) =>
          buffer.update(edit, source) catch {
            @core.LexError(msg) => {
              token_buf.val = None
              last_diags.val = []
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
            }
          }
        None =>
          try {
            let buffer = @core.TokenBuffer::new(
              source,
              tokenize_fn=tokenize,
              eof_token=spec.eof_token,
            )
            token_buf.val = Some(buffer)
            buffer.get_tokens()
          } catch {
            @core.LexError(msg) => {
              last_diags.val = []
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
            }
          }
      }
      let damaged_range = @core.Range::new(edit.start, edit.new_end())
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          damaged_range.start,
          damaged_range.end,
          tokens.length(),
          fn(i) { tokens[i].token },
          fn(i) { tokens[i].start },
          spec,
        ),
      )
      let (new_cst, diagnostics, reuse_count) = @core.parse_tokens_indexed(
        source,
        tokens.length(),
        fn(i) { tokens[i].token },
        fn(i) { tokens[i].start },
        fn(i) { tokens[i].end },
        spec,
        cursor~,
        prev_diagnostics=Some(last_diags.val),
        interner=Some(interner),
        node_interner=Some(node_interner),
      )
      last_diags.val = diagnostics
      let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
      @incremental.ParseOutcome::Tree(new_syntax, reuse_count)
    },
    to_ast=fn(syntax) { to_ast(syntax) },
    on_lex_error=fn(_msg) { derive_lex_error_ast(grammar) },
  )
  @incremental.IncrementalParser::new(source, lang)
}

///|
/// Create a ParserDb from a Grammar.
pub fn[T, K, Ast : Eq] new_parser_db(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @pipeline.ParserDb[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let to_ast = grammar.to_ast
  let lang : @pipeline.Language[Ast] = @pipeline.Language::from_closures(
    parse_source=fn(s) {
      try tokenize(s) catch {
        @core.LexError(msg) => {
          let (cst, _, _) = @core.parse_tokens_indexed(
            "",
            0,
            fn(_) { spec.eof_token },
            fn(_) { 0 },
            fn(_) { 0 },
            spec,
          )
          @pipeline.CstStage::{
            cst,
            diagnostics: ["tokenization: " + msg],
            is_lex_error: true,
          }
        }
      } noraise {
        tokens => {
          let (cst, diags, _) = @core.parse_tokens_indexed(
            s,
            tokens.length(),
            fn(i) { tokens[i].token },
            fn(i) { tokens[i].start },
            fn(i) { tokens[i].end },
            spec,
          )
          @pipeline.CstStage::{
            cst,
            diagnostics: diags.map(fn(d) {
              d.message +
              " [" +
              d.start.to_string() +
              "," +
              d.end.to_string() +
              "]"
            }),
            is_lex_error: false,
          }
        }
      }
    },
    to_ast=fn(n) { to_ast(n) },
    on_lex_error=fn(_msg) { derive_lex_error_ast(grammar) },
  )
  @pipeline.ParserDb::new(source, lang)
}
