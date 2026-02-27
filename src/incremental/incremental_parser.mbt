// Incremental parser based on Wagner-Graham damage tracking algorithm
// for lambda calculus
//
// References:
// - Wagner-Graham (1998): https://harmonia.cs.berkeley.edu/papers/twagner-parsing.pdf
//
// Strategy: Wagner-Graham damage tracking with whole-tree reuse
// or full reparse. Appropriate for recursive descent + small grammars.

///|
/// Incremental parser state
///
/// **Lifetime:** `IncrementalParser` is designed to be created once per document
/// and kept alive for the document's editing session. The internal `Interner`
/// accumulates one entry per distinct `(kind, text)` token pair ever seen; this
/// is bounded by the document's token vocabulary, not by edit count. The internal
/// `NodeInterner` accumulates one entry per distinct structural subtree ever seen;
/// this is bounded by the document's subtree vocabulary, not by edit count.
///
/// For scenarios where the same `IncrementalParser` instance is reused across
/// unrelated documents (e.g., a long-lived LSP process that re-uses parser
/// objects), call `interner_clear()` between documents to release stale entries.
pub struct IncrementalParser {
  mut source : String // Current source text
  mut tree : @ast.AstNode? // output-only: last parse result (never consumed as parse input)
  mut syntax_tree : @seam.SyntaxNode? // Current syntax tree (for subtree reuse)
  mut token_buffer : @lexer.TokenBuffer? // Incremental token buffer
  mut last_reuse_count : Int // Number of nodes reused in last parse
  mut last_diagnostics : Array[@core.Diagnostic[@token.Token]] // Prior parse diagnostics for reuse replay
  priv interner : @seam.Interner // session-scoped token intern table
  priv node_interner : @seam.NodeInterner // session-scoped node intern table
}

///|
/// Create a new incremental parser
pub fn IncrementalParser::new(source : String) -> IncrementalParser {
  {
    source,
    tree: None,
    syntax_tree: None,
    token_buffer: None,
    last_reuse_count: 0,
    last_diagnostics: [],
    interner: @seam.Interner::new(),
    node_interner: @seam.NodeInterner::new(),
  }
}

///|
/// Number of distinct tokens currently interned. For diagnostics and tests.
pub fn IncrementalParser::interner_size(self : IncrementalParser) -> Int {
  self.interner.size()
}

///|
/// Number of distinct structural subtrees currently interned. For diagnostics and tests.
pub fn IncrementalParser::node_interner_size(self : IncrementalParser) -> Int {
  self.node_interner.size()
}

///|
/// Clear both intern tables, releasing all cached token and node entries.
///
/// Only needed when reusing the same `IncrementalParser` across unrelated
/// documents. For normal single-document use this is never required, since the
/// parser is created once per document and the intern tables stay bounded by
/// that document's vocabulary.
pub fn IncrementalParser::interner_clear(self : IncrementalParser) -> Unit {
  self.interner.clear()
  self.node_interner.clear()
}

///|
/// Perform initial full parse
pub fn IncrementalParser::parse(self : IncrementalParser) -> @ast.AstNode {
  let tree = try {
    let buffer = @lexer.TokenBuffer::new(self.source)
    self.token_buffer = Some(buffer)
    // Parse through CST for subtree reuse support
    let (cst, diagnostics) = @parse.parse_cst_recover(
      self.source,
      interner=Some(self.interner),
      node_interner=Some(self.node_interner),
    )
    let syntax = @seam.SyntaxNode::from_cst(cst)
    self.syntax_tree = Some(syntax)
    self.last_reuse_count = 0
    self.last_diagnostics = diagnostics
    let parsed_tree = @parse.syntax_node_to_ast_node(syntax, Ref::new(0))
    parsed_tree
  } catch {
    @lexer.TokenizationError(msg) => {
      let error_msg = "Tokenization error: " + msg
      self.syntax_tree = None
      self.token_buffer = None
      self.last_reuse_count = 0
      self.last_diagnostics = []
      @ast.AstNode::error(error_msg, 0, 0)
    }
  }
  self.tree = Some(tree)
  tree
}

///|
/// Apply an edit and incrementally reparse
///
/// This implements the Wagner-Graham incremental parsing algorithm:
/// 1. Update source text
/// 2. Identify damaged region (edit range)
/// 3. Reparse damaged region, reusing whole tree where possible
pub fn IncrementalParser::edit(
  self : IncrementalParser,
  edit : @core.Edit,
  new_source : String,
) -> @ast.AstNode {
  // Step 1: Update source
  self.source = new_source

  // Step 1.5: Update token buffer incrementally
  let tokens = match self.token_buffer {
    Some(buffer) =>
      buffer.update(edit, self.source) catch {
        @lexer.TokenizationError(msg) => {
          let error_msg = "Tokenization error: " + msg
          let tree = @ast.AstNode::error(error_msg, 0, 0)
          self.tree = Some(tree)
          self.syntax_tree = None
          self.token_buffer = None
          self.last_reuse_count = 0
          self.last_diagnostics = []
          return tree
        }
      }
    None => {
      // No token buffer yet - try full tokenize
      let buffer = @lexer.TokenBuffer::new(self.source) catch {
        @lexer.TokenizationError(msg) => {
          let error_msg = "Tokenization error: " + msg
          let tree = @ast.AstNode::error(error_msg, 0, 0)
          self.tree = Some(tree)
          self.syntax_tree = None
          self.token_buffer = None
          self.last_reuse_count = 0
          self.last_diagnostics = []
          return tree
        }
      }
      self.token_buffer = Some(buffer)
      match self.token_buffer {
        Some(b) => b.get_tokens()
        None => []
      }
    }
  }

  // Ensure initial parse has been done
  if self.syntax_tree is None {
    return self.parse()
  }

  // Compute damaged range directly from edit
  let damaged_range = @core.Range::new(edit.start, edit.new_end())
  let new_tree = self.incremental_reparse(new_source, damaged_range, tokens)
  self.tree = Some(new_tree)
  new_tree
}

///|
/// Incremental reparse with Wagner-Graham approach and subtree reuse
///
/// Strategy:
/// 1. Attempt whole-tree reuse if damage is completely outside tree bounds
/// 2. Otherwise use cursor-based subtree reuse during parsing
fn IncrementalParser::incremental_reparse(
  self : IncrementalParser,
  source : String,
  damaged_range : @core.Range,
  tokens : Array[@token.TokenInfo],
) -> @ast.AstNode {
  // Create cursor from old CST for subtree reuse
  let cursor = match self.syntax_tree {
    Some(old_syntax) =>
      Some(
        @parse.make_reuse_cursor(
          old_syntax.cst_node(),
          damaged_range.start,
          damaged_range.end,
          tokens,
        ),
      )
    None => None
  }

  // Parse with cursor-based reuse
  let (new_cst, diagnostics, reuse_count) = @parse.parse_cst_recover_with_tokens(
    source,
    tokens,
    cursor,
    prev_diagnostics=Some(self.last_diagnostics),
    interner=Some(self.interner),
    node_interner=Some(self.node_interner),
  )

  // Update stored syntax tree and reuse stats
  let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
  self.syntax_tree = Some(new_syntax)
  self.last_reuse_count = reuse_count
  self.last_diagnostics = diagnostics

  // Convert to AstNode
  @parse.syntax_node_to_ast_node(new_syntax, Ref::new(0))
}

///|
/// Get the current parse tree
pub fn IncrementalParser::get_tree(self : IncrementalParser) -> @ast.AstNode? {
  self.tree
}

///|
/// Get the current source
pub fn IncrementalParser::get_source(self : IncrementalParser) -> String {
  self.source
}

///|
/// Get parser statistics
pub fn IncrementalParser::stats(self : IncrementalParser) -> String {
  "IncrementalParser { source_length: " +
  self.source.length().to_string() +
  " }"
}

///|
/// Get the number of nodes reused in the last parse
pub fn IncrementalParser::get_last_reuse_count(self : IncrementalParser) -> Int {
  self.last_reuse_count
}
