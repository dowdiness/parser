// Root package facade for dowdiness/parser
//
// This module re-exports the primary API entry points. For the full API,
// import subpackages directly:
//
//   dowdiness/parser/token        - Token, TokenInfo
//   dowdiness/parser/core         - Edit, Range, ReuseSlot (shared primitives)
//   dowdiness/parser/ast          - AstNode, AstKind, Term, Bop
//   dowdiness/parser/lexer        - tokenize, TokenBuffer
//   dowdiness/parser/syntax       - SyntaxKind enum (token + node kind names)
//   dowdiness/parser/parser       - parse, parse_tree, parse_with_error_recovery
//   dowdiness/parser/incremental  - IncrementalParser, DamageTracker
//   dowdiness/parser/viz          - DotNode (trait), to_dot[T : DotNode]
//   dowdiness/parser/lambda       - LambdaParserDb, LambdaLanguage, DotNode impl for AstNode
//   dowdiness/parser/pipeline     - ParserDb — reactive incremental pipeline

// ── Parsing ──────────────────────────────────────────────────

///|
/// Parse a source string into an abstract syntax tree (Term).
pub fn parse(source : String) -> @ast.Term raise {
  @parse.parse(source)
}

///|
/// Parse a source string into a concrete AST tree with positions.
pub fn parse_tree(source : String) -> @ast.AstNode raise {
  @parse.parse_tree(source)
}

///|
/// Parse a source string with error recovery, returning a tree and diagnostics.
pub fn parse_with_error_recovery(
  source : String,
) -> (@ast.AstNode, Array[String]) {
  @parse.parse_with_error_recovery(source)
}

// ── Tokenization ─────────────────────────────────────────────

///|
/// Tokenize a source string into an array of token info.
pub fn tokenize(source : String) -> Array[@token.TokenInfo[@token.Token]] raise {
  @lexer.tokenize(source)
}

// ── Incremental Parsing ──────────────────────────────────────

///|
/// Create a new incremental parser for the given source.
pub fn incremental(source : String) -> @incremental.IncrementalParser {
  @incremental.IncrementalParser::new(source)
}

// ── Visualization ────────────────────────────────────────────

///|
/// Convert a AST node tree to DOT format for Graphviz visualization.
pub fn ast_node_to_dot(node : @ast.AstNode) -> String {
  @lambda.to_dot(node)
}
