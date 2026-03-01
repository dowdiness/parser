///|
/// Complete grammar description — the three things that vary per language.
///
/// Everything else (TokenBuffer lifecycle, ReuseCursor construction,
/// diagnostic formatting, lex error handling) is derived by the factories.
///
/// Define one per grammar as a module-level `let` and pass it to
/// `new_incremental_parser` or `new_parser_db`.
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  to_ast : (@seam.SyntaxNode) -> Ast
}

///|
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  tokenize~ : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
) -> Grammar[T, K, Ast] {
  { spec, tokenize, to_ast }
}
