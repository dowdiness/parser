// Lambda Calculus language specification for the generic parser infrastructure.

///|
/// The LanguageSpec for Lambda Calculus.
/// Created once at module init, reused across all parses (zero per-parse allocation).
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  @syntax.SyntaxKind::to_raw,
  fn(t) { t == @token.EOF },
  fn(t) { t == @token.Whitespace },
  fn(a, b) { a == b },
  @token.print_token,
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
  raw_is_trivia=fn(raw) { raw == @syntax.WhitespaceToken.to_raw() },
  raw_is_error=fn(raw) { raw == @syntax.ErrorToken.to_raw() },
  green_token_matches=(raw, text, tok) => {
    match @syntax.SyntaxKind::from_raw(raw) {
      IntToken => if tok is Integer(i) { text == i.to_string() } else { false }
      IdentToken => if tok is Identifier(name) { name == text } else { false }
      _ =>
        match syntax_kind_to_token_kind(raw) {
          Some(expected) => expected == tok
          None => false
        }
    }
  },
)
