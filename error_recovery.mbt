// Error recovery for parsing
// Wraps parse_tree with try-catch to produce partial trees on failure

///|
/// Parse with error recovery (returns partial tree with error nodes)
pub fn parse_with_error_recovery(input : String) -> (TermNode, Array[String]) {
  let errors : Array[String] = []
  let tree = parse_tree(input) catch {
    TokenizationError(msg) => {
      let error_msg = "Tokenization error: " + msg
      errors.push(error_msg)
      TermNode::error(error_msg, 0, 0)
    }
    ParseError(msg, token) => {
      let error_msg = "Parse error: " + msg + " at token " + print_token(token)
      errors.push(error_msg)
      TermNode::error(error_msg, 0, 0)
    }
    e => {
      let error_msg = "Unexpected error: " + e.to_string()
      errors.push(error_msg)
      TermNode::error(error_msg, 0, 0)
    }
  }
  (tree, errors)
}

///|
/// Parse pre-tokenized input with error recovery
pub fn parse_with_error_recovery_tokens(
  tokens : Array[TokenInfo],
) -> (TermNode, Array[String]) {
  let errors : Array[String] = []
  let tree = parse_tree_from_tokens(tokens) catch {
    ParseError(msg, token) => {
      let error_msg = "Parse error: " + msg + " at token " + print_token(token)
      errors.push(error_msg)
      TermNode::error(error_msg, 0, 0)
    }
    e => {
      let error_msg = "Unexpected error: " + e.to_string()
      errors.push(error_msg)
      TermNode::error(error_msg, 0, 0)
    }
  }
  (tree, errors)
}

///|
/// Check if a tree contains any error nodes
pub fn has_errors(tree : TermNode) -> Bool {
  match tree.kind {
    TermKind::Error(_) => true
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
pub fn collect_errors(tree : TermNode) -> Array[String] {
  let errors : Array[String] = []
  fn collect(node : TermNode, acc : Array[String]) -> Unit {
    match node.kind {
      TermKind::Error(msg) => acc.push(msg)
      TermKind::Int(_)
      | TermKind::Var(_)
      | TermKind::Lam(_)
      | TermKind::App
      | TermKind::Bop(_)
      | TermKind::If => ()
    }
    for child in node.children {
      collect(child, acc)
    }
  }

  collect(tree, errors)
  errors
}
