///|
/// Concrete language implementation for lambda calculus.
/// Implements the `@pipeline.Parseable` trait by combining tokenize + parse
/// into a single `parse_source` call, erasing `@token.Token` from callers.
pub struct LambdaLanguage {}

///|
pub impl @pipeline.Parseable for LambdaLanguage with parse_source(_, s) {
  try @lexer.tokenize(s) catch {
    @core.LexError(msg) => {
      let (cst, _, _) = parse_cst_recover_with_tokens("", [], None)
      @pipeline.CstStage::{
        cst,
        diagnostics: ["tokenization: " + msg],
        is_lex_error: true,
      }
    }
  } noraise {
    tokens => {
      let (cst, diags, _) = parse_cst_recover_with_tokens(
        s,
        tokens,
        None,
      )
      @pipeline.CstStage::{
        cst,
        diagnostics: diags.map(d => {
          d.message + " [" + d.start.to_string() + "," + d.end.to_string() + "]"
        }),
        is_lex_error: false,
      }
    }
  }
}

///|
/// Convenience constructor — produces the full `Language[AstNode]` vtable.
pub fn lambda_language() -> @pipeline.Language[@ast.AstNode] {
  @pipeline.Language::from(
    LambdaLanguage::{  },
    to_ast=fn(n) { syntax_node_to_ast_node(n, Ref::new(0)) },
    on_lex_error=fn(msg) { @ast.AstNode::error(msg, 0, 0) },
  )
}

///|
/// Lambda calculus `ParserDb` — convenience wrapper over the generic pipeline.
/// Callers get the same `new / set_source / cst / diagnostics / term` API
/// as the lambda-specific `@incremental.ParserDb`, backed by the generic
/// two-memo pipeline.
pub struct LambdaParserDb {
  priv db : @pipeline.ParserDb[@ast.AstNode]
}

///|
pub fn LambdaParserDb::new(source : String) -> LambdaParserDb {
  { db: @pipeline.ParserDb::new(source, lambda_language()) }
}

///|
pub fn LambdaParserDb::set_source(
  self : LambdaParserDb,
  source : String,
) -> Unit {
  self.db.set_source(source)
}

///|
pub fn LambdaParserDb::cst(self : LambdaParserDb) -> @pipeline.CstStage {
  self.db.cst()
}

///|
pub fn LambdaParserDb::diagnostics(self : LambdaParserDb) -> Array[String] {
  self.db.diagnostics()
}

///|
pub fn LambdaParserDb::term(self : LambdaParserDb) -> @ast.AstNode {
  self.db.term()
}
