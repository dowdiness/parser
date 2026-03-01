// Root package facade for dowdiness/parser
//
// This module re-exports the primary API entry points. For the full API,
// import subpackages directly:
//
//   dowdiness/parser/examples/lambda/token   - Token, TokenInfo
//   dowdiness/parser/core                    - Edit, Range, ReuseSlot (shared primitives)
//   dowdiness/parser/examples/lambda/ast     - AstNode, AstKind, Term, Bop
//   dowdiness/parser/examples/lambda/lexer   - tokenize, TokenBuffer
//   dowdiness/parser/examples/lambda/syntax  - SyntaxKind enum (token + node kind names)
//   dowdiness/parser/examples/lambda         - parse, parse_tree, parse_with_error_recovery,
//                                             lambda_grammar, to_dot
//   dowdiness/parser/bridge                  - Grammar[T,K,Ast], new_incremental_parser, new_parser_db
//   dowdiness/parser/incremental             - IncrementalParser, DamageTracker
//   dowdiness/parser/viz                     - DotNode (trait), to_dot[T : DotNode]
//   dowdiness/parser/pipeline                - ParserDb — reactive incremental pipeline

// ── Parsing ──────────────────────────────────────────────────

///|
/// Parse a source string into an abstract syntax tree (Term).
pub fn parse(source : String) -> @ast.Term raise {
  @lambda.parse(source)
}

///|
/// Parse a source string into a concrete AST tree with positions.
pub fn parse_tree(source : String) -> @ast.AstNode raise {
  @lambda.parse_tree(source)
}

///|
/// Parse a source string with error recovery, returning a tree and diagnostics.
pub fn parse_with_error_recovery(
  source : String,
) -> (@ast.AstNode, Array[String]) {
  @lambda.parse_with_error_recovery(source)
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
pub fn incremental(
  source : String,
) -> @incremental.IncrementalParser[@ast.AstNode] {
  @bridge.new_incremental_parser(source, @lambda.lambda_grammar)
}

// ── Visualization ────────────────────────────────────────────

///|
/// Convert a AST node tree to DOT format for Graphviz visualization.
pub fn ast_node_to_dot(node : @ast.AstNode) -> String {
  @lambda.to_dot(node)
}
