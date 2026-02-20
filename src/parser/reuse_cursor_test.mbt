// Tests for ReuseCursor

///|
test "ReuseCursor::new creates cursor" {
  let source = "λx.x"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  let damaged_range = @range.Range::new(0, 0) // No damage
  let cursor = make_reuse_cursor(green, damaged_range, tokens)
  inspect(
    @syntax.SyntaxKind::from_raw(cursor.old_tree().kind),
    content="SourceFile",
  )
}

///|
test "ReuseCursor::try_reuse finds node at offset" {
  let source = "x"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  // No damage
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)

  // Try to find VarRef at offset 0
  // Get the VarRef kind from the parsed tree itself
  let var_ref_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  let result = cursor.try_reuse(var_ref_kind, 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse returns None for wrong kind" {
  let source = "x"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)

  // Try to find IntLiteral at offset 0 (but it's a VarRef)
  let int_kind = @syntax.IntLiteral.to_raw()
  let result = cursor.try_reuse(int_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse returns None for damaged node" {
  let source = "x"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  // Damage includes position 0
  let damaged_range = @range.Range::new(0, 1)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)

  // Get the VarRef kind
  let var_ref_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  // Node is within damaged range, should not reuse
  let result = cursor.try_reuse(var_ref_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse returns None for adjacent damage" {
  let source = "x"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  // Damage starts right after node ends (adjacent)
  let damaged_range = @range.Range::new(1, 2)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)
  let var_ref_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  // Node ends at damaged_range.start, should not reuse
  // (trailing context may have changed)
  let result = cursor.try_reuse(var_ref_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse works for IntLiteral" {
  let source = "42"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)
  let int_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  let result = cursor.try_reuse(int_kind, 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse works for LambdaExpr" {
  let source = "λx.x"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)
  let lambda_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  let result = cursor.try_reuse(lambda_kind, 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse works for ParenExpr" {
  let source = "(x)"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)
  let paren_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  let result = cursor.try_reuse(paren_kind, 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse works for nested VarRef" {
  let source = "λx.y"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)

  let var_ref_kind = @syntax.VarRef.to_raw()
  // VarRef "y" is at byte offset 3
  let result = cursor.try_reuse(var_ref_kind, 3, 3)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse checks leading token mismatch" {
  let source = "x"
  let (green, _) = parse_green_recover(source)
  // Create tokens for different source
  let new_tokens = @lexer.tokenize("y")
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, new_tokens)
  let var_ref_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  // Leading token "y" doesn't match node's first token "x"
  let result = cursor.try_reuse(var_ref_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse rejects integer value mismatch" {
  let source = "12"
  let (green, _) = parse_green_recover(source)
  // Different integer token at same location should not match.
  let new_tokens = @lexer.tokenize("34")
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, new_tokens)
  let int_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  let result = cursor.try_reuse(int_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse rejects identifier boundary merge by follow token" {
  let source = "x y"
  let (green, _) = parse_green_recover(source)
  // Follow token after first VarRef changed from Identifier("y") to EOF.
  let merged_tokens = @lexer.tokenize("xy")
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, merged_tokens)
  let var_ref_kind = @syntax.VarRef.to_raw()
  let result = cursor.try_reuse(var_ref_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor::try_reuse rejects integer boundary merge by follow token" {
  let source = "1 2"
  let (green, _) = parse_green_recover(source)
  // Follow token after first IntLiteral changed from Integer(2) to EOF.
  let merged_tokens = @lexer.tokenize("12")
  let damaged_range = @range.Range::new(10, 10)
  let cursor = make_reuse_cursor(green, damaged_range, merged_tokens)
  let int_kind = @syntax.IntLiteral.to_raw()
  let result = cursor.try_reuse(int_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor reuse for separated regions" {
  // Test that nodes in one part of the tree can be reused when
  // damage is in another part
  let source = "a + b"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  // Damage only affects the "b" part (positions 4-5)
  let damaged_range = @range.Range::new(4, 5)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)

  // Get VarRef kind
  let var_ref_kind = @syntax.VarRef.to_raw()
  // "a" at position 0 should be reusable
  let result = cursor.try_reuse(var_ref_kind, 0, 0)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor no reuse when node overlaps damage" {
  let source = "abc"
  let (green, _) = parse_green_recover(source)
  let tokens = @lexer.tokenize(source)
  // Damage is in the middle of the identifier
  let damaged_range = @range.Range::new(1, 2)
  let cursor = make_reuse_cursor(green, damaged_range, tokens)
  let var_ref_kind = match green.children[0] {
    @green_tree.GreenElement::Node(n) => n.kind
    @green_tree.GreenElement::Token(_) => abort("Expected node")
  }
  // The VarRef spans 0-3, overlaps with damage 1-2
  let result = cursor.try_reuse(var_ref_kind, 0, 0)
  inspect(result is None, content="true")
}

///|
test "ReuseCursor verify kind extraction works" {
  // Sanity: expected kinds are stable and round-trip through RawKind.
  inspect(@syntax.SyntaxKind::from_raw(@syntax.VarRef.to_raw()), content="VarRef")
  inspect(
    @syntax.SyntaxKind::from_raw(@syntax.IntLiteral.to_raw()),
    content="IntLiteral",
  )
  inspect(
    @syntax.SyntaxKind::from_raw(@syntax.LambdaExpr.to_raw()),
    content="LambdaExpr",
  )
}
