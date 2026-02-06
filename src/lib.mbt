// Root package facade for dowdiness/parser
//
// This module re-exports the primary API entry points. For the full API,
// import subpackages directly:
//
//   dowdiness/parser/token        - Token, TokenInfo
//   dowdiness/parser/range        - Range
//   dowdiness/parser/edit         - Edit
//   dowdiness/parser/term         - Term, TermNode, TermKind, Bop
//   dowdiness/parser/lexer        - tokenize, TokenBuffer
//   dowdiness/parser/syntax       - GreenNode, GreenToken, SyntaxKind
//   dowdiness/parser/parser       - parse, parse_tree, parse_with_error_recovery
//   dowdiness/parser/incremental  - IncrementalParser, DamageTracker
//   dowdiness/parser/crdt         - CRDTNode, ParsedDocument
//   dowdiness/parser/viz          - term_node_to_dot

// ── Parsing ──────────────────────────────────────────────────

///|
/// Parse a source string into an abstract term.
pub fn parse(source : String) -> @term.Term raise {
  @parse.parse(source)
}

///|
/// Parse a source string into a concrete term tree with positions.
pub fn parse_tree(source : String) -> @term.TermNode raise {
  @parse.parse_tree(source)
}

///|
/// Parse a source string with error recovery, returning a tree and diagnostics.
pub fn parse_with_error_recovery(
  source : String
) -> (@term.TermNode, Array[String]) {
  @parse.parse_with_error_recovery(source)
}

// ── Tokenization ─────────────────────────────────────────────

///|
/// Tokenize a source string into an array of token info.
pub fn tokenize(
  source : String
) -> Array[@token.TokenInfo] raise {
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
/// Convert a term node tree to DOT format for Graphviz visualization.
pub fn term_node_to_dot(node : @term.TermNode) -> String {
  @viz.term_node_to_dot(node)
}

// ── CRDT ─────────────────────────────────────────────────────

///|
/// Convert a term node tree to a CRDT representation.
pub fn ast_to_crdt(node : @term.TermNode) -> @crdt.CRDTNode {
  @crdt.ast_to_crdt(node)
}

///|
/// Reconstruct source code from a CRDT tree.
pub fn crdt_to_source(node : @crdt.CRDTNode) -> String {
  @crdt.crdt_to_source(node)
}
