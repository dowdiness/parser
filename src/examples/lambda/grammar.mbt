///|
/// Lambda calculus grammar description.
///
/// This is the complete integration surface — a single value that
/// bridge factories consume to produce IncrementalParser or ParserDb.
pub let lambda_grammar : @bridge.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.AstNode,
] = @bridge.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  to_ast=fn(s) { syntax_node_to_ast_node(s, Ref::new(0)) },
)
