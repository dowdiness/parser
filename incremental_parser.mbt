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
pub struct IncrementalParser {
  mut source : String // Current source text
  mut tree : TermNode? // Current parse tree
  mut token_buffer : TokenBuffer? // Incremental token buffer
}

///|
/// Create a new incremental parser
pub fn IncrementalParser::new(source : String) -> IncrementalParser {
  { source, tree: None, token_buffer: None }
}

///|
/// Perform initial full parse
pub fn IncrementalParser::parse(self : IncrementalParser) -> TermNode {
  let tree = try {
    let buffer = TokenBuffer::new(self.source)
    self.token_buffer = Some(buffer)
    let tokens = match self.token_buffer {
      Some(b) => b.get_tokens()
      None => []
    }
    let (parsed_tree, _errors) = parse_with_error_recovery_tokens(tokens)
    parsed_tree
  } catch {
    TokenizationError(msg) => {
      let error_msg = "Tokenization error: " + msg
      TermNode::error(error_msg, 0, 0)
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
  edit : Edit,
  new_source : String,
) -> TermNode {
  // Step 1: Update source
  self.source = new_source

  // Step 1.5: Update token buffer incrementally
  let tokens = match self.token_buffer {
    Some(buffer) =>
      buffer.update(edit, self.source) catch {
        TokenizationError(msg) => {
          let error_msg = "Tokenization error: " + msg
          let tree = TermNode::error(error_msg, 0, 0)
          self.tree = Some(tree)
          self.token_buffer = None
          return tree
        }
      }
    None => {
      // No token buffer yet - try full tokenize
      let buffer = TokenBuffer::new(self.source) catch {
        TokenizationError(msg) => {
          let error_msg = "Tokenization error: " + msg
          let tree = TermNode::error(error_msg, 0, 0)
          self.tree = Some(tree)
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

  // Step 2: Get old tree (if any)
  let old_tree = match self.tree {
    Some(t) => t
    None =>
      // No existing tree, do full parse
      return self.parse()
  }

  // Step 3: Adjust old tree positions based on edit
  let adjusted_tree = self.adjust_tree_positions(old_tree, edit)

  // Step 4: Identify damaged range using Wagner-Graham algorithm
  let damage = DamageTracker::new(edit)
  damage.expand_for_tree(adjusted_tree)

  // Step 5: Incremental reparse
  let damaged_range = damage.range()
  let new_tree = self.incremental_reparse(
    new_source, damaged_range, adjusted_tree, tokens,
  )
  self.tree = Some(new_tree)
  new_tree
}

///|
/// Incremental reparse with Wagner-Graham approach
///
/// Strategy:
/// 1. Attempt whole-tree reuse if damage is completely outside tree bounds
/// 2. Otherwise full reparse
fn IncrementalParser::incremental_reparse(
  self : IncrementalParser,
  source : String,
  damaged_range : Range,
  adjusted_tree : TermNode,
  tokens : Array[TokenInfo],
) -> TermNode {
  // Attempt whole-tree reuse: Can we reuse the entire tree?
  // Only safe if damage is completely outside tree bounds
  if self.can_reuse_node(adjusted_tree, damaged_range) &&
    adjusted_tree.start == 0 &&
    adjusted_tree.end == source.length() {
    // Tree is completely unchanged - reuse it
    return adjusted_tree
  }

  // Full reparse
  let (tree, _errors) = parse_with_error_recovery_tokens(tokens)
  tree
}

///|
/// Check if a node can be reused (Wagner-Graham range check)
///
/// A node can be reused if it doesn't overlap with the damaged range.
/// Overlap occurs when: node.start < damaged.end AND node.end > damaged.start
fn IncrementalParser::can_reuse_node(
  _self : IncrementalParser,
  node : TermNode,
  damaged_range : Range,
) -> Bool {
  // Node is reusable if it doesn't overlap the damaged range
  // No overlap means: node ends before damage starts OR node starts after damage ends
  node.end <= damaged_range.start || node.start >= damaged_range.end
}

///|
/// Adjust tree positions after an edit
///
/// Wagner-Graham position adjustment:
/// - Nodes before edit: unchanged
/// - Nodes overlapping edit: marked as damaged
/// - Nodes after edit: shifted by delta
fn IncrementalParser::adjust_tree_positions(
  self : IncrementalParser,
  tree : TermNode,
  edit : Edit,
) -> TermNode {
  let delta = edit.delta()

  //  tree.end <= edit.start Doesn't Work!
  //  When tree.end == edit.start, the new content is inserted immediately adjacent to the tree. In lambda calculus grammar, adjacent terms form function application: (\x.x) 5 → App(Lam, Int).

  //  tree.end < edit.start means:
  //  - Only reuse the tree if there's a gap between the tree and the edit
  //  - If tree.end == edit.start (adjacent insertion), force a reparse to check for combinations
  if tree.end < edit.start {
    // Node is entirely before edit, no change needed
    tree
  } else if tree.start > edit.old_end {
    // Node is entirely after edit, shift positions
    let adjusted_children = tree.children.map(fn(child) {
      self.adjust_tree_positions(child, edit)
    })
    TermNode::new(
      tree.kind,
      tree.start + delta,
      tree.end + delta,
      tree.node_id,
      adjusted_children,
    )
  } else {
    // Node overlaps edit range - will need reparsing
    // For now, just adjust children and mark range as needing update
    let adjusted_children = tree.children.map(fn(child) {
      self.adjust_tree_positions(child, edit)
    })
    TermNode::new(
      tree.kind,
      tree.start,
      tree.end,
      tree.node_id,
      adjusted_children,
    )
  }
}

///|
/// Get the current parse tree
pub fn IncrementalParser::get_tree(self : IncrementalParser) -> TermNode? {
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
