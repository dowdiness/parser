// Integration tests for Interner wiring in IncrementalParser

///|
/// Verify parse result is structurally unchanged after adding the interner.
/// The tree printed form must equal a full reparse with no interner.
test "Interner: initial parse result unchanged with interner" {
  let parser = @loom.new_incremental_parser("λf.λx.f (f x)", lambda_grammar)
  let tree = parser.parse()
  let full_tree = parse_tree("λf.λx.f (f x)")
  inspect(@ast.print_ast_node(tree), content=@ast.print_ast_node(full_tree))
}

///|
/// Verify incremental edit result is structurally unchanged with interner.
test "Interner: edit result unchanged with interner" {
  let parser = @loom.new_incremental_parser("λx.x + 1", lambda_grammar)
  let _ = parser.parse()

  let edit = @core.Edit::replace(7, 8, 8) // "1" -> "2"
  let incr_tree = parser.edit(edit, "λx.x + 2")
  let full_tree = parse_tree("λx.x + 2")
  inspect(
    @ast.print_ast_node(incr_tree),
    content=@ast.print_ast_node(full_tree),
  )
}

///|
/// Verify interner size is bounded by vocabulary, not proportional to token
/// count. Parsing "x + x + x + x + x" has many tokens but only a small
/// vocabulary {x, +}, so the interner should not grow unboundedly.
test "Interner: size bounded by vocabulary" {
  // Source with many repeated tokens: 5 copies of "x" and 4 copies of "+"
  // Vocabulary is only 2 distinct token types: (Ident, "x") and (Plus, "+")
  let parser = @loom.new_incremental_parser(
    "x + x + x + x + x", lambda_grammar,
  )
  let _ = parser.parse()

  // The interner must hold no more than the number of distinct (kind, text)
  // pairs. We don't know exact counts (whitespace tokens exist too), but it
  // must be far smaller than the 9 non-whitespace tokens. Use 10 as a safe
  // upper bound on distinct pairs for this small source.
  inspect(parser.interner_size() <= 10, content="true")
}

///|
/// Verify interner size does not grow when re-parsing identical source.
/// After a no-op edit the vocabulary is the same, so size must not increase.
test "Interner: size does not grow on identical re-parse" {
  let parser = @loom.new_incremental_parser("λx.x", lambda_grammar)
  let _ = parser.parse()
  let size_after_initial = parser.interner_size()

  // Zero-length edit: source is unchanged
  let edit = @core.Edit::insert(4, 0)
  let _ = parser.edit(edit, "λx.x")
  let size_after_noop = parser.interner_size()

  // Size must not have grown
  inspect(size_after_noop <= size_after_initial, content="true")
}

///|
/// Verify interner size stays positive (tokens are interned) after a parse.
test "Interner: size is positive after non-empty parse" {
  let parser = @loom.new_incremental_parser("x", lambda_grammar)
  let _ = parser.parse()
  inspect(parser.interner_size() > 0, content="true")
}
