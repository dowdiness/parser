// Integration tests for NodeInterner wiring in IncrementalParser

///|
test "NodeInterner: size is positive after non-empty parse" {
  let parser = LambdaIncrementalParser::new("λx.x")
  let _ = parser.parse()
  inspect(parser.node_interner_size() > 0, content="true")
}

///|
test "NodeInterner: interner_clear resets node_interner_size to zero" {
  let parser = LambdaIncrementalParser::new("λx.x")
  let _ = parser.parse()
  parser.interner_clear()
  inspect(parser.node_interner_size(), content="0")
}

///|
test "NodeInterner: interner_clear resets both token and node interners" {
  let parser = LambdaIncrementalParser::new("λf.λx.f (f x)")
  let _ = parser.parse()
  parser.interner_clear()
  inspect(parser.interner_size(), content="0")
  inspect(parser.node_interner_size(), content="0")
}

///|
test "NodeInterner: size does not grow on identical re-parse" {
  let parser = LambdaIncrementalParser::new("λx.x")
  let _ = parser.parse()
  let size_after_initial = parser.node_interner_size()

  // Zero-length edit: source is unchanged
  let edit = @core.Edit::insert(4, 0)
  let _ = parser.edit(edit, "λx.x")
  let size_after_noop = parser.node_interner_size()

  inspect(size_after_noop <= size_after_initial, content="true")
}

///|
test "NodeInterner: parse result unchanged after adding node_interner" {
  let parser = LambdaIncrementalParser::new("λf.λx.f (f x)")
  let tree = parser.parse()
  let full_tree = parse_tree("λf.λx.f (f x)")
  inspect(@ast.print_ast_node(tree), content=@ast.print_ast_node(full_tree))
}
