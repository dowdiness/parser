// Generic parser infrastructure — ParserContext[T, K]

///|
/// Generic token with source position. T is the language-specific token type.
pub struct TokenInfo[T] {
  token : T
  start : Int // byte offset, inclusive
  end   : Int // byte offset, exclusive
} derive(Show)

///|
/// A parse diagnostic (error or warning) with source position.
pub struct Diagnostic {
  message : String
  start   : Int
  end     : Int
} derive(Show)

///|
/// Describes one language to the generic parser infrastructure.
/// Create one instance at module init — it is reused across all parses.
///
/// Fields:
///   kind_to_raw     — maps your SyntaxKind to the green tree's RawKind (an Int)
///   token_is_eof    — returns true for the end-of-input sentinel token
///   tokens_equal    — equality check (needed because T has no Eq constraint)
///   whitespace_kind — the SyntaxKind for whitespace trivia nodes
///   error_kind      — the SyntaxKind for error tokens/nodes
///   root_kind       — the SyntaxKind for the root node (e.g. SourceFile)
///   eof_token       — the T value returned when past end of input
pub struct LanguageSpec[T, K] {
  kind_to_raw     : (K) -> @green_tree.RawKind
  token_is_eof    : (T) -> Bool
  tokens_equal    : (T, T) -> Bool
  whitespace_kind : K
  error_kind      : K
  root_kind       : K
  eof_token       : T
}

///|
test "TokenInfo stores token with position" {
  let info : TokenInfo[String] = { token: "hello", start: 0, end: 5 }
  inspect(info.start, content="0")
  inspect(info.end, content="5")
  inspect(info.token, content="hello")
}

///|
test "Diagnostic stores message and position" {
  let d : Diagnostic = { message: "unexpected token", start: 3, end: 7 }
  inspect(d.message, content="unexpected token")
}
