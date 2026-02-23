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

///|
test "ReuseCursor::try_reuse accepts post-damage node when follow token unchanged" {
  // In "\\x.y", VarRef("y") is emitted with NO leading whitespace: the "."
  // is a non-whitespace token so flush_trivia emits nothing before "y".
  // VarRef("y") starts at byte 3, text_len=1 — its byte offset matches the
  // token position — so seek_node_at(3, VarRef) finds it.
  //
  // Edit: replace "x" with "y" at byte 1 (delta=0). New source: "\\y.y".
  // Damage covers [0, 2) (the lambda+param "\\x"). VarRef("y")@[3,4] is
  // post-damage (3 > damaged_range.end=2). Its old follow is EOF; new follow
  // (token index 4) is also EOF. Trailing context matches → reuse accepted.
  let (green, _) = parse_green_recover("\\x.y")
  let new_tokens = @lexer.tokenize("\\y.y")
  let damaged_range = @range.Range::new(0, 2)
  let cursor = make_reuse_cursor(green, damaged_range, new_tokens)
  // byte_offset=3 (where "y" appears in new source), token_pos=3 (fourth token)
  let result = cursor.try_reuse(@syntax.VarRef.to_raw(), 3, 3)
  inspect(result is Some(_), content="true")
}

///|
test "ReuseCursor::try_reuse rejects post-damage node when follow token changes" {
  // Same old tree "\\x.y" and damage [0,2).
  // New source: "\\y.y z" — adds " z" after the body, changing the follow
  // token of VarRef("y") from EOF to Identifier("z").
  // seek_node_at(3, VarRef) finds VarRef("y")@3 (post-damage, outside [0,2)).
  // leading_token_matches passes (token[3] is Identifier("y") == old text "y").
  // trailing_context_matches: old_follow=None (EOF), new_follow=Some(Identifier("z"))
  // → (None, Some) → false → reuse rejected via follow-token check.
  let (green, _) = parse_green_recover("\\x.y")
  let new_tokens = @lexer.tokenize("\\y.y z")
  let damaged_range = @range.Range::new(0, 2)
  let cursor = make_reuse_cursor(green, damaged_range, new_tokens)
  let result = cursor.try_reuse(@syntax.VarRef.to_raw(), 3, 3)
  inspect(result is None, content="true")
}

///|
/// Test that try_reuse handles a Whitespace token at self.position correctly.
///
/// Setup: old source "x + y" (BinaryExpr with two VarRef nodes).
/// New source is the same "x + y" with damage limited to [2, 3) — only the "+"
/// character.  The token layout is:
///   [Identifier("x")@0, Whitespace(" ")@[1,2], Plus("+")@2,
///    Whitespace(" ")@[3,4], Identifier("y")@4, EOF@5]
///
/// VarRef("x") at [0,1) is outside damage [2,3) and is reused.  After reuse,
/// the advance loop stops at tokens[1] (Whitespace at start=1, which is NOT
/// strictly less than node_end=1), so position stays at 1 — a Whitespace
/// token.  The parser then emits "+" and calls parse_atom for the right
/// operand with position=3, another Whitespace token.  In GreenParser::
/// try_reuse the single-scan loop must skip that Whitespace before finding
/// Identifier("y"), demonstrating the whitespace-inclusive position handling.
///
/// The test verifies:
///   - reuse_count >= 1: VarRef("x") is reused, confirming the overall reuse
///     machinery works in this expression.
///   - errors.length() == 0: no parse errors.
///   - new_tree == full_tree: incremental result matches a full reparse,
///     confirming correctness after the whitespace scan.
test "try_reuse handles Whitespace token at self.position correctly" {
  let source = "x + y"
  let (old_tree, _) = parse_green_recover(source)
  let new_tokens = @lexer.tokenize(source)
  // Damage covers only the "+" character [2, 3).
  // VarRef("x")@[0,1] is pre-damage and reusable.
  // After reusing VarRef("x"), position advances to the Whitespace token.
  // The subsequent try_reuse call for the right operand exercises the
  // whitespace-skipping scan loop with position pointing at Whitespace.
  let damaged_range = @range.Range::new(2, 3)
  let cursor = make_reuse_cursor(old_tree, damaged_range, new_tokens)
  let (new_tree, errors, reuse_count) = parse_green_with_cursor(
    source, new_tokens, cursor,
  )
  // No parse errors
  inspect(errors.length(), content="0")
  // VarRef("x") before the damage was reused
  inspect(reuse_count >= 1, content="true")
  // Result matches a full reparse
  let (full_tree, _) = parse_green_recover(source)
  inspect(new_tree == full_tree, content="true")
}

///|
test "ReuseCursor verify kind extraction works" {
  // Sanity: expected kinds are stable and round-trip through RawKind.
  inspect(
    @syntax.SyntaxKind::from_raw(@syntax.VarRef.to_raw()),
    content="VarRef",
  )
  inspect(
    @syntax.SyntaxKind::from_raw(@syntax.IntLiteral.to_raw()),
    content="IntLiteral",
  )
  inspect(
    @syntax.SyntaxKind::from_raw(@syntax.LambdaExpr.to_raw()),
    content="LambdaExpr",
  )
}
