// Tests for positioned parser with source tracking

///|
test "parse_tree simple integer" {
  let node = parse_tree("42")
  let printed = @ast.print_ast_node(node)
  inspect(printed, content="42")
  inspect(node.start, content="0")
  inspect(node.end, content="2")
}

///|
test "parse_tree simple variable" {
  let node = parse_tree("x")
  let printed = @ast.print_ast_node(node)
  inspect(printed, content="x")
  inspect(node.start, content="0")
  inspect(node.end, content="1")
}

///|
test "parse_tree identity function" {
  let node = parse_tree("λx.x")
  let printed = @ast.print_ast_node(node)
  inspect(printed, content="(λx. x)")
  inspect(node.start, content="0")
  // Should span from λ to the end of body
  inspect(node.end >= 3, content="true")
}

///|
test "parse_tree binary operator" {
  let node = parse_tree("1 + 2")
  let printed = @ast.print_ast_node(node)
  inspect(printed, content="(1 + 2)")
  inspect(node.children.length(), content="2")
  // Check left operand
  inspect(node.children[0].start, content="0")
  // Check right operand
  inspect(node.children[1].start, content="4")
}

///|
test "parse_tree application" {
  let node = parse_tree("f x")
  let printed = @ast.print_ast_node(node)
  inspect(printed, content="(f x)")
  inspect(node.children.length(), content="2")
}

///|
test "parse_tree if-then-else" {
  let node = parse_tree("if x then y else z")
  let printed = @ast.print_ast_node(node)
  inspect(printed, content="if x then y else z")
  inspect(node.children.length(), content="3")
}

///|
test "parse_tree complex expression" {
  let node = parse_tree("λf.λx.f x")
  let printed = @ast.print_ast_node(node)
  inspect(printed.contains("λf"), content="true")
  inspect(printed.contains("λx"), content="true")
  // Outer lambda should have one child (the inner lambda)
  inspect(node.children.length(), content="1")
}

///|
test "parse_tree node IDs are unique" {
  let node = parse_tree("f x y")
  // Root node
  let root_id = node.node_id
  // Left child (f x)
  let left_id = node.children[0].node_id
  // Right child (y)
  let right_id = node.children[1].node_id
  // All IDs should be different
  inspect(root_id != left_id, content="true")
  inspect(root_id != right_id, content="true")
  inspect(left_id != right_id, content="true")
}

///|
test "parse_tree preserves source positions" {
  let node = parse_tree("  x  +  y  ")
  // x should start around position 2
  let left_child = node.children[0]
  inspect(left_child.start >= 2, content="true")
  inspect(left_child.end >= 3, content="true")
  // y should start around position 8
  let right_child = node.children[1]
  inspect(right_child.start >= 7, content="true")
}

///|
test "parse_tree: lambda span excludes leading whitespace in application" {
  // Regression: concrete syntax tree emits whitespace before λ inside the LambdaExpr
  // node. The conversion must skip it so Lam start points at λ, not the space.
  let node = parse_tree("f  λx.x")
  // Root is App(f, λx.x)
  inspect(node.kind, content="App")
  let lam = node.children[1]
  inspect(lam.kind, content="Lam(\"x\")")
  // λ starts at position 3 (after "f  "), not 1
  inspect(lam.start, content="3")
}

///|
test "parse_tree: if-expr span excludes leading whitespace" {
  // IfExpr as body of lambda — space after "." is inside the IfExpr green node
  let node = parse_tree("\\x. if x then y else z")
  inspect(node.kind, content="Lam(\"x\")")
  let if_node = node.children[0]
  inspect(if_node.kind, content="If")
  // "if" starts at position 4, not 3 (the space after ".")
  inspect(if_node.start, content="4")
  // end should be at the end of "z" (position 22)
  inspect(if_node.end, content="22")
}

///|
test "parse_tree: paren-expr span excludes leading whitespace" {
  // ParenExpr inside an application with leading whitespace
  let node = parse_tree("f  (x)")
  inspect(node.kind, content="App")
  let paren = node.children[1]
  // ParenExpr unwraps to Var, but span should cover ( to )
  inspect(paren.kind, content="Var(\"x\")")
  // "(" starts at position 3
  inspect(paren.start, content="3")
  // ")" ends at position 6
  inspect(paren.end, content="6")
}
