// Error recovery for parsing
// Uses the integrated error-recovering green parser

///|
/// Parse with error recovery (returns partial tree with error nodes)
pub fn parse_with_error_recovery(
  input : String,
) -> (@term.TermNode, Array[String]) {
  let errors : Array[String] = []
  let result = parse_green_recover(input) catch {
    @lexer.TokenizationError(msg) => {
      let error_msg = "Tokenization error: " + msg
      errors.push(error_msg)
      return (@term.TermNode::error(error_msg, 0, 0), errors)
    }
  }
  let (green, diagnostics) = result
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
  let tree = green_to_term_node(green, 0, Ref::new(0))
  (tree, errors)
}

///|
/// Parse pre-tokenized input with error recovery
pub fn parse_with_error_recovery_tokens(
  tokens : Array[@token.TokenInfo],
) -> (@term.TermNode, Array[String]) {
  let errors : Array[String] = []
  let tree = parse_tree_from_tokens(tokens) catch {
    ParseError(msg, token) => {
      let error_msg = "Parse error: " +
        msg +
        " at token " +
        @token.print_token(token)
      errors.push(error_msg)
      @term.TermNode::error(error_msg, 0, 0)
    }
    e => {
      let error_msg = "Unexpected error: " + e.to_string()
      errors.push(error_msg)
      @term.TermNode::error(error_msg, 0, 0)
    }
  }
  (tree, errors)
}

///|
/// Check if a tree contains any error nodes
pub fn has_errors(tree : @term.TermNode) -> Bool {
  match tree.kind {
    @term.TermKind::Error(_) => true
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
pub fn collect_errors(tree : @term.TermNode) -> Array[String] {
  let errors : Array[String] = []
  fn collect(node : @term.TermNode, acc : Array[String]) -> Unit {
    match node.kind {
      @term.TermKind::Error(msg) => acc.push(msg)
      @term.TermKind::Int(_)
      | @term.TermKind::Var(_)
      | @term.TermKind::Lam(_)
      | @term.TermKind::App
      | @term.TermKind::Bop(_)
      | @term.TermKind::If => ()
    }
    for child in node.children {
      collect(child, acc)
    }
  }

  collect(tree, errors)
  errors
}
