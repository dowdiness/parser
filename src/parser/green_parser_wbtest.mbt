///|
test "panic GreenParser::finish_node without matching start_node" {
  let parser = GreenParser::new([], "")
  parser.finish_node()
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
