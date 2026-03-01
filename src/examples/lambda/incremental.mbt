///|
/// Build an IncrementalLanguage[@ast.AstNode] for lambda calculus.
///
/// Token buffer and diagnostics state are captured as Refs inside closures,
/// keeping IncrementalParser[@ast.AstNode] language-agnostic.
///
/// Note: each IncrementalParser must receive its own IncrementalLanguage
/// instance. Sharing one instance across multiple parsers will corrupt both
/// parsers' token-buffer and diagnostics state.
pub fn lambda_incremental_language() -> @incremental.IncrementalLanguage[
  @ast.AstNode,
] {
  let token_buf : Ref[@core.TokenBuffer[@token.Token]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[@token.Token]]] = Ref::new([])
  @incremental.IncrementalLanguage::new(
    full_parse=(source, interner, node_interner) => {
      try {
        let buffer = @core.TokenBuffer::new(
          source,
          tokenize_fn=@lexer.tokenize,
          eof_token=@token.EOF,
        )
        token_buf.val = Some(buffer)
        let tokens = buffer.get_tokens()
        let (cst, diagnostics, _) = parse_cst_recover_with_tokens(
          source,
          tokens,
          None,
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
      // Step 1: Update token buffer incrementally
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
              tokenize_fn=@lexer.tokenize,
              eof_token=@token.EOF,
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
      // Step 2: Build reuse cursor from old CST and damaged range
      let damaged_range = @core.Range::new(edit.start, edit.new_end())
      let cursor = Some(
        make_reuse_cursor(
          old_syntax.cst_node(),
          damaged_range.start,
          damaged_range.end,
          tokens,
        ),
      )
      // Step 3: Incremental parse via @core
      let (new_cst, diagnostics, reuse_count) = parse_cst_recover_with_tokens(
        source,
        tokens,
        cursor,
        prev_diagnostics=Some(last_diags.val),
        interner=Some(interner),
        node_interner=Some(node_interner),
      )
      last_diags.val = diagnostics
      let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
      @incremental.ParseOutcome::Tree(new_syntax, reuse_count)
    },
    to_ast=syntax => syntax_node_to_ast_node(syntax, Ref::new(0)),
    on_lex_error=msg => @ast.AstNode::error(msg, 0, 0),
  )
}
