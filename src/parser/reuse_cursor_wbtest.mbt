// Whitebox tests for ReuseCursor internals

///|
test "collect_old_tokens excludes ErrorToken from old_tokens" {
  // "λ.x" triggers error recovery: a zero-width ErrorToken is inserted
  // for the missing identifier between λ and .
  let (green, diagnostics) = parse_green_recover("λ.x")
  inspect(diagnostics.length() > 0, content="true") // confirm error tree
  let tokens = @lexer.tokenize("λ.x")
  let damaged_range = @range.Range::new(10, 10) // no damage
  let cursor = make_reuse_cursor(green, damaged_range, tokens)
  // ErrorToken must not appear in old_tokens: it is not a real syntactic
  // token and its presence would cause trailing_context_matches to silently
  // reject all reuse via fall-through (latent maintenance hazard).
  let error_token_raw = @syntax.ErrorToken.to_raw()
  let mut error_count = 0
  for t in cursor.old_tokens {
    if t.kind == error_token_raw {
      error_count = error_count + 1
    }
  }
  inspect(error_count, content="0")
}
