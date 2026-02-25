// Parser for Lambda Calculus expressions

///|
pub suberror ParseError {
  ParseError(String, @token.Token)
}

///|
/// Parse the input string into a Term (without position information)
///
/// This is a wrapper around parse_tree that discards position information.
pub fn parse(input : String) -> @ast.Term raise {
  let node = parse_tree(input)
  @ast.node_to_term(node)
}

///|
/// Parse the input string into an AstNode with position tracking
///
/// Routes through the concrete syntax tree (CST) as the canonical intermediate
/// representation: parse_cst → cst_to_ast_node.
pub fn parse_tree(input : String) -> @ast.AstNode raise {
  let cst = parse_cst(input)
  cst_to_ast_node(cst, 0, Ref::new(0))
}
