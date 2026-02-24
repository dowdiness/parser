///|
test "panic finish_node without matching start_node" {
  let ctx = @core.ParserContext::new([], "", lambda_spec)
  ctx.finish_node()
}

///|
test "parse_green_recover: with interner matches without interner" {
  let source = "λx.x + x"
  let (plain, _) = parse_green_recover(source)
  let interner = @green_tree.Interner::new()
  let (interned, _) = parse_green_recover(source, interner=Some(interner))
  inspect(plain == interned, content="true")
}

///|
test "parse_green_recover: interner populated after parse" {
  let source = "x + x"
  let interner = @green_tree.Interner::new()
  let _ = parse_green_recover(source, interner=Some(interner))
  inspect(interner.size() > 0, content="true")
}

///|
test "parse_green: raises with offending token, not EOF" {
  // Regression guard: parse_green must preserve the offending token in
  // ParseError. "λ.x" is missing a parameter; the Dot at offset 1 is the
  // offending token.
  let _ = parse_green("λ.x") catch {
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
  // Only reached if parse_green didn't raise — should not happen
  inspect(false, content="true")
}

///|
test "parse_green_recover_with_tokens: uses supplied tokens, not re-tokenization" {
  // Regression guard: the old stub called parse_green_recover(source) and
  // would abort() on TokenizationError for temporarily invalid source text.
  // The function must parse the supplied token stream, never re-tokenize.
  // "@invalid" raises TokenizationError if passed to @lexer.tokenize, but
  // the function must return normally when given valid tokens.
  let tokens = @lexer.tokenize("x + y")
  let (_, errors, reuse_count) = parse_green_recover_with_tokens(
    "@invalid",
    tokens,
    None,
  )
  inspect(errors.length(), content="0")
  inspect(reuse_count, content="0")
}

///|
test "parse_green_with_cursor: uses supplied tokens, not re-tokenization" {
  // Same regression guard for parse_green_with_cursor.
  let source = "x + y"
  let tokens = @lexer.tokenize(source)
  let cursor = @core.ReuseCursor::new(
    parse_green_recover(source).0,
    0,
    0,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    lambda_spec,
  )
  let (_, errors, _reuse_count) = parse_green_with_cursor(
    "@invalid", tokens, cursor,
  )
  inspect(errors.length(), content="0")
}

///|
test "parse_green_recover_with_tokens: with interner matches without" {
  let source = "λx.x"
  let tokens = @lexer.tokenize(source)
  let (plain, _, _) = parse_green_recover_with_tokens(source, tokens, None)
  let interner = @green_tree.Interner::new()
  let (interned, _, _) = parse_green_recover_with_tokens(
    source,
    tokens,
    None,
    interner=Some(interner),
  )
  inspect(plain == interned, content="true")
}
