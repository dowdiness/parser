// Lambda Calculus language specification for the generic parser infrastructure.

///|
/// The LanguageSpec for Lambda Calculus.
/// Created once at module init, reused across all parses (zero per-parse allocation).
let lambda_spec : @core.LanguageSpec[@token.Token, @syntax.SyntaxKind] = @core.LanguageSpec::new(
  @syntax.SyntaxKind::to_raw,
  fn(t) { t == @token.EOF },
  fn(t) { t == @token.Whitespace },
  fn(a, b) { a == b },
  @syntax.WhitespaceToken,
  @syntax.ErrorToken,
  @syntax.SourceFile,
  @token.EOF,
)
