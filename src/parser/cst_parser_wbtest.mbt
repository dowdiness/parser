///|
test "panic finish_node without matching start_node" {
  let ctx = @core.ParserContext::new([], "", lambda_spec)
  ctx.finish_node()
}

///|
test "parse_cst_recover: with interner matches without interner" {
  let source = "λx.x + x"
  let (plain, _) = parse_cst_recover(source)
  let interner = @seam.Interner::new()
  let (interned, _) = parse_cst_recover(source, interner=Some(interner))
  inspect(plain == interned, content="true")
}

///|
test "parse_cst_recover: interner populated after parse" {
  let source = "x + x"
  let interner = @seam.Interner::new()
  let _ = parse_cst_recover(source, interner=Some(interner))
  inspect(interner.size() > 0, content="true")
}

///|
test "parse_cst: raises with offending token, not EOF" {
  // Regression guard: parse_cst must preserve the offending token in
  // ParseError. "λ.x" is missing a parameter; the Dot at offset 1 is the
  // offending token.
  let _ = parse_cst("λ.x") catch {
    ParseError(_, token) => {
      inspect(token == @token.EOF, content="false")
      inspect(token == @token.Dot, content="true")
      return
    }
    _ => {
      // Any error other than ParseError is a test failure
      inspect(false, content="true")
      return
    }
  }
  // Only reached if parse_cst didn't raise — should not happen
  inspect(false, content="true")
}

///|
test "parse_cst_recover_with_tokens: uses supplied tokens, not re-tokenization" {
  // Regression guard: the old stub called parse_cst_recover(source) and
  // would abort() on TokenizationError for temporarily invalid source text.
  // The function must parse the supplied token stream, never re-tokenize.
  // "@invalid" raises TokenizationError if passed to @lexer.tokenize, but
  // the function must return normally when given valid tokens.
  let tokens = @lexer.tokenize("x + y")
  let (_, errors, reuse_count) = parse_cst_recover_with_tokens(
    "@invalid",
    tokens,
    None,
  )
  inspect(errors.length(), content="0")
  inspect(reuse_count, content="0")
}

///|
test "parse_cst_with_cursor: uses supplied tokens, not re-tokenization" {
  // Same regression guard for parse_cst_with_cursor.
  let source = "x + y"
  let tokens = @lexer.tokenize(source)
  let cursor = @core.ReuseCursor::new(
    parse_cst_recover(source).0,
    0,
    0,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    lambda_spec,
  )
  let (_, errors, _reuse_count) = parse_cst_with_cursor(
    "@invalid", tokens, cursor,
  )
  inspect(errors.length(), content="0")
}

///|
test "reuse fires: VarRef unchanged after identifier edit" {
  // Old: "x + y"  →  New: "z + y"  (damage [0,1): only "x" changed)
  // VarRef("y") at [3,5) is outside damage and text is unchanged → reused.
  // reuse_count > 0 confirms the cursor path is live, not a stub.
  let old_source = "x + y"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "z + y"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 0, 1, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
  inspect(reuse_count > 0, content="true")
}

///|
test "reuse fires: lambda body VarRef unchanged after parameter edit" {
  // Old: "λx.y"  →  New: "λz.y"  (damage [2,3): only the parameter byte changed)
  // LambdaExpr overlaps damage → body runs normally.
  // VarRef("y") at [4,5) inside the body is outside damage → reused.
  let old_source = "λx.y"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "λz.y"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 2, 3, new_tokens)
  let (new_tree, errors, reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
  inspect(reuse_count > 0, content="true")
}

///|
test "parse_cst_with_cursor: identifier boundary merge matches full reparse" {
  // Old: "x y" -> New: "xy" (space deleted at [1,2) in old source).
  // Reuse must not produce a stale split; result must match full reparse.
  let old_source = "x y"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "xy"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens)
  let (new_tree, errors, _reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
}

///|
test "parse_cst_with_cursor: integer boundary merge matches full reparse" {
  // Old: "1 2" -> New: "12" (space deleted at [1,2) in old source).
  // Reuse must not keep two stale IntLiteral nodes.
  let old_source = "1 2"
  let (old_tree, _) = parse_cst_recover(old_source)
  let new_source = "12"
  let new_tokens = @lexer.tokenize(new_source)
  let cursor = make_reuse_cursor(old_tree, 1, 2, new_tokens)
  let (new_tree, errors, _reuse_count) = parse_cst_with_cursor(
    new_source, new_tokens, cursor,
  )
  let (full_tree, _) = parse_cst_recover(new_source)
  inspect(new_tree == full_tree, content="true")
  inspect(errors.length(), content="0")
}

///|
test "parse_cst_recover_with_tokens: with interner matches without" {
  let source = "λx.x"
  let tokens = @lexer.tokenize(source)
  let (plain, _, _) = parse_cst_recover_with_tokens(source, tokens, None)
  let interner = @seam.Interner::new()
  let (interned, _, _) = parse_cst_recover_with_tokens(
    source,
    tokens,
    None,
    interner=Some(interner),
  )
  inspect(plain == interned, content="true")
}

///|
test "parse_cst_with_cursor: preserves prior diagnostic messages on reused invalid subtree" {
  let source = "λ.x"
  let tokens = @lexer.tokenize(source)
  let (old_tree, old_errors) = parse_cst_recover(source)
  inspect(old_errors.length(), content="1")
  inspect(old_errors[0].message, content="Expected parameter after λ")

  let cursor = make_reuse_cursor(old_tree, 99, 99, tokens)
  let (_, errors, reuse_count) = parse_cst_with_cursor(
    source,
    tokens,
    cursor,
    prev_diagnostics=Some(old_errors),
  )
  inspect(reuse_count > 0, content="true")
  inspect(errors.length(), content="1")
  inspect(errors[0].message, content="Expected parameter after λ")
}

///|
test "parse_cst_recover_with_tokens: preserves prior diagnostic messages on reused invalid subtree" {
  let source = "λ.x"
  let tokens = @lexer.tokenize(source)
  let (old_tree, old_errors) = parse_cst_recover(source)
  inspect(old_errors.length(), content="1")
  inspect(old_errors[0].message, content="Expected parameter after λ")

  let cursor = make_reuse_cursor(old_tree, 99, 99, tokens)
  let (_, errors, reuse_count) = parse_cst_recover_with_tokens(
    source,
    tokens,
    Some(cursor),
    prev_diagnostics=Some(old_errors),
  )
  inspect(reuse_count > 0, content="true")
  inspect(errors.length(), content="1")
  inspect(errors[0].message, content="Expected parameter after λ")
}
