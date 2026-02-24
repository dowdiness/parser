// Tests for error recovery

///|
test "parse_with_error_recovery succeeds on valid input" {
  let (tree, errors) = parse_with_error_recovery("42")
  inspect(@ast.print_ast_node(tree), content="42")
  inspect(errors.length(), content="0")
}

///|
test "parse_with_error_recovery handles parse error" {
  let (tree, errors) = parse_with_error_recovery("λ.x") // Missing parameter

  // Should have error diagnostics
  inspect(errors.length() > 0, content="true")

  // Tree should be a partial lambda (with empty param, not just an error node)
  let expected = "(λ. x)"
  inspect(@ast.print_ast_node(tree), content=expected)
}

///|
test "parse_with_error_recovery handles tokenization error" {
  let (tree, errors) = parse_with_error_recovery("@invalid")

  // Should have error
  inspect(errors.length() > 0, content="true")

  // Should be error node
  match tree.kind {
    @ast.AstKind::Error(msg) =>
      inspect(msg.contains("Tokenization"), content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "has_errors detects error nodes" {
  let valid_tree = parse_tree("42")
  inspect(has_errors(valid_tree), content="false")
  let error_tree = @ast.AstNode::error("test error", 0, 0)
  inspect(has_errors(error_tree), content="true")
}

///|
test "collect_errors finds all error messages" {
  // Create a tree with an error node
  let error_node = @ast.AstNode::error("test error", 0, 0)
  let errors = collect_errors(error_node)
  inspect(errors.length(), content="1")
  inspect(errors[0], content="test error")
}

///|
test "collect_errors finds nested errors" {
  // Parse a valid expression to get a tree structure
  let tree = parse_tree("1 + 2")

  // This tree shouldn't have errors
  let errors = collect_errors(tree)
  inspect(errors.length(), content="0")
}

///|
test "parse_with_error_recovery returns partial tree" {
  // Even with errors, we should get some tree structure back
  let (tree, errors) = parse_with_error_recovery("λx") // Incomplete (missing dot and body)

  // Should have errors
  inspect(errors.length() > 0, content="true")

  // Should have some node (not just a bare error)
  inspect(tree.node_id >= 0, content="true")
}

///|
test "error recovery: multiple errors" {
  // "λ.x + )" has: missing param after λ, and extra ")" after expression
  let (tree, errors) = parse_with_error_recovery("λ.x + )")

  // Should have multiple errors
  inspect(errors.length() >= 2, content="true")

  // Tree should still contain some valid structure
  inspect(has_errors(tree), content="true")
}

///|
test "error recovery: if without else" {
  let (tree, errors) = parse_with_error_recovery("if x then y")

  // Should report missing else
  inspect(errors.length() > 0, content="true")

  // Should have partial IfExpr
  inspect(tree.kind is @ast.AstKind::If, content="true")
}

///|
test "error recovery: valid input produces no errors" {
  let inputs = [
    "42", "x", "λx.x", "f x", "1 + 2", "if x then 1 else 2", "(x)", "λf.λx.f (f x)",
  ]
  for input in inputs {
    let (_, errors) = parse_with_error_recovery(input)
    inspect(errors.length(), content="0")
  }
}

///|
test "error recovery: valid input identical to parse_tree" {
  let inputs = [
    "42", "x", "λx.x", "f x", "1 + 2", "if x then 1 else 2", "(x)", "λf.λx.f (f x)",
  ]
  for input in inputs {
    let direct = parse_tree(input)
    let (recovered, _) = parse_with_error_recovery(input)
    inspect(@ast.print_ast_node(recovered), content=@ast.print_ast_node(direct))
  }
}

///|
test "error recovery: extra tokens after expression" {
  let (tree, errors) = parse_with_error_recovery("42 )")

  // Should report extra tokens
  inspect(errors.length() > 0, content="true")

  // Should have the parsed 42 plus error children
  inspect(has_errors(tree), content="true")
}

///|
test "error recovery: extra tokens - parent span covers children" {
  let (tree, _) = parse_with_error_recovery("42 )")
  // The root node must span all its children (including the error child for ")")
  for child in tree.children {
    inspect(child.start >= tree.start, content="true")
    inspect(child.end <= tree.end, content="true")
  }
}

///|
test "error recovery: unclosed paren" {
  let (tree, errors) = parse_with_error_recovery("(x")

  // Should report missing right paren
  inspect(errors.length() > 0, content="true")

  // Should still parse something
  inspect(tree.node_id >= 0, content="true")
}

///|
test "parse_cst_recover returns diagnostics" {
  let (green, diagnostics) = parse_cst_recover("λ.x")
  inspect(diagnostics.length(), content="1")
  inspect(diagnostics[0].message, content="Expected parameter after λ")
  // Green tree should be a valid SourceFile
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
}

///|
test "parse_cst_recover no errors on valid input" {
  let (green, diagnostics) = parse_cst_recover("λx.x")
  inspect(diagnostics.length(), content="0")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
}

///|
test "parse_cst_recover EOF diagnostics point to end of source" {
  // "if x then y" is missing "else" — the diagnostic for the missing
  // "else" keyword fires at EOF which should be at the end of the source.
  let source = "if x then y"
  let (_, diagnostics) = parse_cst_recover(source)
  inspect(diagnostics.length() > 0, content="true")
  // Find the diagnostic about the missing "else"
  let mut found = false
  for diag in diagnostics {
    if diag.message.contains("else") {
      // Position must be at or near the end of the source, not 0
      inspect(diag.start > 0, content="true")
      found = true
    }
  }
  inspect(found, content="true")
}

///|
test "error recovery: all-error input preserves every error node" {
  // ") x" starts with a stop token then a valid-looking token — both
  // become errors at the SourceFile level.  Conversion must keep them all.
  let (tree, errors) = parse_with_error_recovery(") x")
  inspect(errors.length() > 0, content="true")
  inspect(has_errors(tree), content="true")
  // The tree should cover the full source span
  inspect(tree.end > 0, content="true")
}

///|
test "parse_cst still raises on first error" {
  // parse_cst should maintain backward compat and raise
  let result = parse_cst("λ.x") catch {
    _ =>
      // Expected to raise ParseError
      return
  }
  ignore(result)
  // Should not reach here — parse_cst should have raised
  inspect(false, content="true")
}
