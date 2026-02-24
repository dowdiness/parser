// Error recovery for parsing
// Uses the integrated error-recovering CST parser

///|
/// Parse with error recovery (returns partial tree with error nodes)
pub fn parse_with_error_recovery(
  input : String,
) -> (@ast.AstNode, Array[String]) {
  let errors : Array[String] = []
  let result = parse_cst_recover(input) catch {
    @lexer.TokenizationError(msg) => {
      let error_msg = "Tokenization error: " + msg
      errors.push(error_msg)
      return (@ast.AstNode::error(error_msg, 0, 0), errors)
    }
  }
  let (cst, diagnostics) = result
  // Map diagnostics to error strings — include token name for readability
  for diag in diagnostics {
    errors.push(
      "Parse error: " +
      diag.message +
      " (got " +
      @token.print_token(diag.got_token) +
      ")",
    )
  }
  let tree = cst_to_ast_node(cst, 0, Ref::new(0))
  (tree, errors)
}

///|
/// Parse pre-tokenized input with error recovery
pub fn parse_with_error_recovery_tokens(
  tokens : Array[@token.TokenInfo],
) -> (@ast.AstNode, Array[String]) {
  let errors : Array[String] = []
  let tree = parse_tree_from_tokens(tokens) catch {
    ParseError(msg, token) => {
      let error_msg = "Parse error: " +
        msg +
        " at token " +
        @token.print_token(token)
      errors.push(error_msg)
      @ast.AstNode::error(error_msg, 0, 0)
    }
    e => {
      let error_msg = "Unexpected error: " + e.to_string()
      errors.push(error_msg)
      @ast.AstNode::error(error_msg, 0, 0)
    }
  }
  (tree, errors)
}

///|
/// Check if a tree contains any error nodes
pub fn has_errors(tree : @ast.AstNode) -> Bool {
  match tree.kind {
    @ast.AstKind::Error(_) => true
    _ => {
      // Check children recursively
      for child in tree.children {
        if has_errors(child) {
          return true
        }
      }
      false
    }
  }
}

///|
/// Collect all error messages from a tree
pub fn collect_errors(tree : @ast.AstNode) -> Array[String] {
  let errors : Array[String] = []
  fn collect(node : @ast.AstNode, acc : Array[String]) -> Unit {
    match node.kind {
      @ast.AstKind::Error(msg) => acc.push(msg)
      @ast.AstKind::Int(_)
      | @ast.AstKind::Var(_)
      | @ast.AstKind::Lam(_)
      | @ast.AstKind::App
      | @ast.AstKind::Bop(_)
      | @ast.AstKind::If => ()
    }
    for child in node.children {
      collect(child, acc)
    }
  }

  collect(tree, errors)
  errors
}
