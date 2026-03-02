///|
// Public API facade for dowdiness/loom.
// A single import gives access to all framework types for both grammar
// authors (LanguageSpec, ParserContext, SyntaxNode) and parser consumers
// (IncrementalParser, ParserDb, Edit, Diagnostic).

///|
// CST types — grammar callbacks receive SyntaxNode; the full green tree is CstNode.
pub using @seam {
  type CstNode,
  type SyntaxNode,
  type SyntaxToken,
  type SyntaxElement,
}

///|
// Core parser primitives
pub using @core {
  type Edit,
  type TokenInfo,
  type Diagnostic,
  type LanguageSpec,
  type ParserContext,
  type TextDelta,
  type LexError,
}

///|
// Incremental engine — the primary parser type consumers interact with
pub using @incremental {type IncrementalParser}

///|
// Reactive pipeline — Signal[String] → Memo[Ast]
pub using @pipeline {type ParserDb}

// Grammar and factory functions (new_incremental_parser, new_parser_db)
// are defined in grammar.mbt and factories.mbt in this package.
