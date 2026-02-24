// Tests for Phase 2 green tree implementation

// ============================================================================
// 1. Basic parsing to green tree
// ============================================================================

///|
test "green tree: simple integer" {
  let green = parse_green("42")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  inspect(green.children.length() > 0, content="true")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IntLiteral")
}

///|
test "green tree: simple variable" {
  let green = parse_green("x")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="VarRef")
}

///|
test "green tree: lambda expression" {
  let green = parse_green("λx.x")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LambdaExpr")
}

///|
test "green tree: application" {
  let green = parse_green("f x")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="AppExpr")
}

///|
test "green tree: binary operation" {
  let green = parse_green("1 + 2")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="BinaryExpr")
}

///|
test "green tree: if-then-else" {
  let green = parse_green("if x then 1 else 2")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IfExpr")
}

// ============================================================================
// 2. ParenExpr node presence - distinguishing x from (x)
// ============================================================================

///|
test "green tree: ParenExpr is present" {
  let green = parse_green("(x)")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  // (x) should have ParenExpr as the outer node
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="ParenExpr")
}

///|
test "green tree: x vs (x) have different structure" {
  let green_bare = parse_green("x")
  let green_paren = parse_green("(x)")
  let bare_child = match green_bare.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  let paren_child = match green_paren.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  // bare x is VarRef, (x) is ParenExpr
  inspect(@syntax.SyntaxKind::from_raw(bare_child.kind), content="VarRef")
  inspect(@syntax.SyntaxKind::from_raw(paren_child.kind), content="ParenExpr")
  // They must be different
  inspect(bare_child.kind != paren_child.kind, content="true")
}

///|
test "green tree: nested parentheses ((x))" {
  let green = parse_green("((x))")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="ParenExpr")
  // The inner expression should also be a ParenExpr
  let mut inner_paren_found = false
  for elem in child.children {
    match elem {
      @seam.CstElement::Node(n) =>
        match @syntax.SyntaxKind::from_raw(n.kind) {
          @syntax.ParenExpr => inner_paren_found = true
          _ => ()
        }
      @seam.CstElement::Token(_) => continue
    }
  }
  inspect(inner_paren_found, content="true")
}

///|
test "green tree: deeply nested parentheses (((1)))" {
  let green = parse_green("(((1)))")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  // Count the nesting depth of ParenExpr
  fn count_paren_depth(node : @seam.CstNode) -> Int {
    match @syntax.SyntaxKind::from_raw(node.kind) {
      @syntax.ParenExpr => {
        for elem in node.children {
          match elem {
            @seam.CstElement::Node(n) => return 1 + count_paren_depth(n)
            @seam.CstElement::Token(_) => continue
          }
        }
        1
      }
      _ => 0
    }
  }

  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(count_paren_depth(child), content="3")
}

// ============================================================================
// 3. Position correctness via SyntaxNode
// ============================================================================

///|
test "green tree: SyntaxNode positions for simple expression" {
  let green = parse_green("x + y")
  let red = @seam.SyntaxNode::from_green(green)
  inspect(red.start(), content="0")
  inspect(red.end(), content="5")
}

///|
test "green tree: SyntaxNode positions for integer" {
  let green = parse_green("42")
  let red = @seam.SyntaxNode::from_green(green)
  inspect(red.start(), content="0")
  inspect(red.end(), content="2")
}

///|
test "green tree: SyntaxNode positions for lambda" {
  let green = parse_green("λx.x")
  let red = @seam.SyntaxNode::from_green(green)
  inspect(red.start(), content="0")
  inspect(red.end(), content="4")
}

///|
test "green tree: SyntaxNode children positions" {
  let green = parse_green("1 + 2")
  let red = @seam.SyntaxNode::from_green(green)
  let children = red.children()
  inspect(children.length(), content="1")
  let binary_expr = children[0]
  inspect(
    @syntax.SyntaxKind::from_raw(binary_expr.kind()),
    content="BinaryExpr",
  )
  inspect(binary_expr.start(), content="0")
  inspect(binary_expr.end(), content="5")
}

///|
test "green tree: SyntaxNode child positions in application" {
  let green = parse_green("f x")
  let red = @seam.SyntaxNode::from_green(green)
  let children = red.children()
  inspect(children.length(), content="1")
  let app_expr = children[0]
  inspect(@syntax.SyntaxKind::from_raw(app_expr.kind()), content="AppExpr")
  let app_children = app_expr.children()
  inspect(app_children.length(), content="2")
  inspect(app_children[0].start(), content="0")
  inspect(app_children[0].end(), content="1")
  inspect(app_children[1].start(), content="1")
  inspect(app_children[1].end(), content="3")
}

// ============================================================================
// 4. Backward compatibility - parse_green_to_term_node matches parse_tree
// ============================================================================

///|
test "green tree: backward compatibility - simple integer" {
  let source = "42"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - variable" {
  let source = "x"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - lambda" {
  let source = "λx.x"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - lambda with body" {
  let source = "λx.x + 1"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - application" {
  let source = "f x"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - nested application" {
  let source = "f x y"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - binary operation" {
  let source = "1 + 2"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - chained binary (same op)" {
  // Note: chained operations with different operators (e.g., "1 + 2 - 3")
  // have a known limitation in green_convert - it uses the first operator for all.
  // This test uses same operator to verify the basic mechanism works.
  let source = "1 + 2 + 3"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - if-then-else" {
  let source = "if x then 1 else 2"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - parenthesized expression" {
  let source = "(x)"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

///|
test "green tree: backward compatibility - complex expression" {
  let source = "λf.λx.f (f x)"
  let term_via_green = parse_green_to_term_node(source)
  let term_direct = parse_tree(source)
  inspect(
    @term.print_term_node(term_via_green),
    content=@term.print_term_node(term_direct),
  )
}

// ============================================================================
// 5. Structural sharing potential - identical tokens have same text
// ============================================================================

///|
test "green tree: identical integer tokens have same text" {
  let green = parse_green("1 + 1")
  fn collect_int_tokens(node : @seam.CstNode) -> Array[String] {
    let tokens : Array[String] = []
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IntToken.to_raw() {
            tokens.push(t.text)
          }
        @seam.CstElement::Node(n) => tokens.append(collect_int_tokens(n))
      }
    }
    tokens
  }

  let int_tokens = collect_int_tokens(green)
  inspect(int_tokens.length(), content="2")
  // Both tokens should have the same text "1"
  inspect(int_tokens[0] == int_tokens[1], content="true")
  inspect(int_tokens[0], content="1")
}

///|
test "green tree: identical identifier tokens have same text" {
  let green = parse_green("x + x")
  fn collect_ident_tokens(node : @seam.CstNode) -> Array[String] {
    let tokens : Array[String] = []
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IdentToken.to_raw() {
            tokens.push(t.text)
          }
        @seam.CstElement::Node(n) => tokens.append(collect_ident_tokens(n))
      }
    }
    tokens
  }

  let ident_tokens = collect_ident_tokens(green)
  inspect(ident_tokens.length(), content="2")
  // Both tokens should have the same text "x"
  inspect(ident_tokens[0] == ident_tokens[1], content="true")
  inspect(ident_tokens[0], content="x")
}

///|
test "green tree: token text is preserved correctly" {
  let green = parse_green("abc + 123")
  fn find_first_ident(node : @seam.CstNode) -> String? {
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IdentToken.to_raw() {
            return Some(t.text)
          } else {
            continue
          }
        @seam.CstElement::Node(n) => {
          let result = find_first_ident(n)
          match result {
            Some(s) => return Some(s)
            None => continue
          }
        }
      }
    }
    None
  }

  fn find_first_int(node : @seam.CstNode) -> String? {
    for elem in node.children {
      match elem {
        @seam.CstElement::Token(t) =>
          if t.kind == @syntax.IntToken.to_raw() {
            return Some(t.text)
          } else {
            continue
          }
        @seam.CstElement::Node(n) => {
          let result = find_first_int(n)
          match result {
            Some(s) => return Some(s)
            None => continue
          }
        }
      }
    }
    None
  }

  inspect(find_first_ident(green), content="Some(\"abc\")")
  inspect(find_first_int(green), content="Some(\"123\")")
}

// ============================================================================
// Additional test cases
// ============================================================================

///|
test "green tree: lambda with application body" {
  let green = parse_green("λf.f x")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LambdaExpr")
}

///|
test "green tree: nested if-then-else" {
  let green = parse_green("if x then if y then 1 else 2 else 3")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IfExpr")
}

///|
test "green tree: parenthesized lambda" {
  let green = parse_green("(λx.x)")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="ParenExpr")
}

///|
test "green tree: application with parenthesized argument" {
  let green = parse_green("f (x)")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="AppExpr")
}

///|
test "green tree: binary with parenthesized operands" {
  let green = parse_green("(1) + (2)")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="BinaryExpr")
}

///|
test "green tree: text_len is computed correctly" {
  let green = parse_green("abc")
  inspect(green.text_len, content="3")
  let green2 = parse_green("1 + 2")
  inspect(green2.text_len, content="5")
}

///|
test "green tree: CstElement kind accessor" {
  let green = parse_green("42")
  let elem = green.children[0]
  inspect(@syntax.SyntaxKind::from_raw(elem.kind()), content="IntLiteral")
}

///|
test "green tree: CstElement text_len accessor" {
  let green = parse_green("42")
  let elem = green.children[0]
  inspect(elem.text_len(), content="2")
}

///|
test "green tree: position comparison" {
  let source = "x + y"
  let term_direct = parse_tree(source)
  let term_via_green = parse_green_to_term_node(source)
  inspect(term_direct.start, content="0")
  inspect(term_direct.end, content="5")
  inspect(term_via_green.start, content="0")
  inspect(term_via_green.end, content="5")
}

///|
test "green tree: structural sharing - identical CstNodes are equal" {
  let green1 = parse_green("x")
  let green2 = parse_green("x")
  let node1 = match green1.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node")
  }
  let node2 = match green2.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node")
  }
  inspect(node1 == node2, content="true")
}

// ============================================================================
// 6. Error recovery in green tree
// ============================================================================

///|
test "green tree: has_green_errors on valid input" {
  let green = parse_green("42")
  inspect(
    green.has_errors(@syntax.ErrorNode.to_raw(), @syntax.ErrorToken.to_raw()),
    content="false",
  )
}

///|
test "green tree: has_green_errors on valid lambda" {
  let green = parse_green("λx.x")
  inspect(
    green.has_errors(@syntax.ErrorNode.to_raw(), @syntax.ErrorToken.to_raw()),
    content="false",
  )
}

///|
test "green tree: error recovery - missing param produces ErrorToken" {
  let (green, diagnostics) = parse_green_recover("λ.x")
  inspect(
    green.has_errors(@syntax.ErrorNode.to_raw(), @syntax.ErrorToken.to_raw()),
    content="true",
  )
  inspect(diagnostics.length(), content="1")
  // Should still have SourceFile > LambdaExpr structure
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LambdaExpr")
}

///|
test "green tree: error recovery - extra tokens wrapped in ErrorNode" {
  let (green, diagnostics) = parse_green_recover("42 )")
  inspect(diagnostics.length() > 0, content="true")
  // SourceFile should have IntLiteral + ErrorNode
  let mut found_int = false
  let mut found_error = false
  for elem in green.children {
    match elem {
      @seam.CstElement::Node(n) =>
        match @syntax.SyntaxKind::from_raw(n.kind) {
          @syntax.IntLiteral => found_int = true
          @syntax.ErrorNode => found_error = true
          _ => ()
        }
      @seam.CstElement::Token(_) => ()
    }
  }
  inspect(found_int, content="true")
  inspect(found_error, content="true")
}

///|
test "green tree: error recovery - missing else in if" {
  let (green, diagnostics) = parse_green_recover("if x then y")
  inspect(diagnostics.length() > 0, content="true")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
  let child = match green.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="IfExpr")
}

///|
test "green tree: error recovery - text_len preserved" {
  let (green, _) = parse_green_recover("λ.x")
  // text_len should cover the entire source
  inspect(green.text_len, content="3")
}

///|
test "green tree: error recovery - multiple errors" {
  let (green, diagnostics) = parse_green_recover("λ.x + )")
  // Should have at least 2 errors: missing param, extra ")"
  inspect(diagnostics.length() >= 2, content="true")
  inspect(@syntax.SyntaxKind::from_raw(green.kind), content="SourceFile")
}

///|
test "green tree: error recovery preserves valid input" {
  // Valid inputs should produce identical trees via recover vs strict
  let inputs = ["42", "x", "λx.x", "f x", "1 + 2", "if x then 1 else 2", "(x)"]
  for input in inputs {
    let strict = parse_green(input)
    let (recovered, diagnostics) = parse_green_recover(input)
    inspect(diagnostics.length(), content="0")
    inspect(strict == recovered, content="true")
  }
}

///|
/// Collect the text of all leaf tokens in a green tree (depth-first).
fn collect_leaf_texts(node : @seam.CstNode) -> String {
  let parts : Array[String] = []
  fn walk(n : @seam.CstNode) -> Unit {
    for elem in n.children {
      match elem {
        @seam.CstElement::Token(t) => parts.push(t.text)
        @seam.CstElement::Node(child) => walk(child)
      }
    }
  }

  walk(node)
  parts.join("")
}

///|
test "parse preserves all whitespace in green tree" {
  let source = "  x + 1  "
  let (tree, _) = parse_green_recover(source)
  let texts = collect_leaf_texts(tree)
  inspect(texts, content="  x + 1  ")
}

///|
test "parse preserves leading and trailing whitespace" {
  let source = "  42  "
  let (tree, _) = parse_green_recover(source)
  let texts = collect_leaf_texts(tree)
  inspect(texts, content="  42  ")
}

///|
test "parse preserves internal whitespace in application" {
  let source = "f  x"
  let (tree, _) = parse_green_recover(source)
  let texts = collect_leaf_texts(tree)
  inspect(texts, content="f  x")
}
