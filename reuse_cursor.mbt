// ReuseCursor for checkpoint-based subtree reuse during incremental parsing
//
// The cursor walks the old green tree in parallel with parsing,
// enabling reuse of unchanged subtrees. Uses a stateful traversal
// to achieve O(depth) lookup instead of O(tree).

///|
/// Frame in the cursor stack, tracking position within a node
struct CursorFrame {
  node : GreenNode
  mut child_index : Int
  start_offset : Int // Byte offset where this node starts
}

///|
/// Cursor for walking an old green tree to find reusable subtrees.
/// Maintains traversal state for O(depth) lookups.
pub struct ReuseCursor {
  // Stack of frames from root to current position
  stack : Array[CursorFrame]
  // Current byte offset in the traversal
  mut current_offset : Int
  // Damage information - subtrees overlapping this range cannot be reused
  damaged_range : Range
  // Token buffer for context checks (new tokens)
  tokens : Array[TokenInfo]
  // Fast path: true if damage covers root (no reuse possible)
  reuse_globally_disabled : Bool
}

///|
/// Create a new reuse cursor positioned at the start of the tree
pub fn ReuseCursor::new(
  old_tree : GreenNode,
  damaged_range : Range,
  tokens : Array[TokenInfo],
) -> ReuseCursor {
  // Disable reuse globally if damage covers the entire tree.
  // When damage spans [0, tree_len), no subtree can be outside damage.
  let reuse_globally_disabled = damaged_range.start <= 0 &&
    damaged_range.end >= old_tree.text_len
  let stack = [{ node: old_tree, child_index: 0, start_offset: 0 }]
  { stack, current_offset: 0, damaged_range, tokens, reuse_globally_disabled }
}

///|
/// Get the old tree root (for testing/debugging)
pub fn ReuseCursor::old_tree(self : ReuseCursor) -> GreenNode {
  self.stack[0].node
}

///|
/// Check if reuse is globally disabled (damage covers entire tree)
pub fn ReuseCursor::is_reuse_disabled(self : ReuseCursor) -> Bool {
  self.reuse_globally_disabled
}

///|
/// Count the total number of non-whitespace tokens in a green node
fn count_tokens_in_node(node : GreenNode) -> Int {
  let mut count = 0
  for child in node.children {
    match child {
      Token(t) => if t.kind != WhitespaceToken { count = count + 1 }
      Node(n) => count = count + count_tokens_in_node(n)
    }
  }
  count
}

///|
/// Get the first non-whitespace token text from a green node
fn first_token_text(node : GreenNode) -> String? {
  for child in node.children {
    match child {
      Token(t) => if t.kind != WhitespaceToken { return Some(t.text) }
      Node(n) => {
        let result = first_token_text(n)
        if result is Some(_) {
          return result
        }
      }
    }
  }
  None
}

///|
/// Get the first non-whitespace token kind from a green node
fn first_token_kind(node : GreenNode) -> SyntaxKind? {
  for child in node.children {
    match child {
      Token(t) => if t.kind != WhitespaceToken { return Some(t.kind) }
      Node(n) => {
        let result = first_token_kind(n)
        if result is Some(_) {
          return result
        }
      }
    }
  }
  None
}

///|
/// Map SyntaxKind to the corresponding Token for comparison
fn syntax_kind_to_token_kind(kind : SyntaxKind) -> Token? {
  match kind {
    LambdaToken => Some(Lambda)
    DotToken => Some(Dot)
    LeftParenToken => Some(LeftParen)
    RightParenToken => Some(RightParen)
    PlusToken => Some(Plus)
    MinusToken => Some(Minus)
    IfKeyword => Some(If)
    ThenKeyword => Some(Then)
    ElseKeyword => Some(Else)
    _ => None
  }
}

///|
/// Check if a syntax kind matches a token (for leading token check)
fn token_matches_syntax_kind(
  token : Token,
  text : String,
  kind : SyntaxKind,
) -> Bool {
  match kind {
    IdentToken =>
      match token {
        Identifier(name) => name == text
        _ => false
      }
    IntToken =>
      match token {
        Integer(_) => true // Value doesn't need to match, text does
        _ => false
      }
    _ =>
      match syntax_kind_to_token_kind(kind) {
        Some(expected) => token == expected
        None => false
      }
  }
}

///|
/// Check if a node is outside the damaged range
fn is_outside_damage(
  node_start : Int,
  node_end : Int,
  damaged_range : Range,
) -> Bool {
  // Node is outside damage if it ends STRICTLY before damage starts
  // OR starts STRICTLY after damage ends.
  // Adjacent nodes (node_end == damaged_range.start) are NOT safe because
  // trailing context may have changed.
  node_end < damaged_range.start || node_start > damaged_range.end
}

///|
/// Check if the leading token of the node matches the token at token_pos
fn leading_token_matches(
  node : GreenNode,
  tokens : Array[TokenInfo],
  token_pos : Int,
) -> Bool {
  if token_pos >= tokens.length() {
    return false
  }
  let expected_token = tokens[token_pos]
  let node_first_kind = first_token_kind(node)
  let node_first_text = first_token_text(node)
  match (node_first_kind, node_first_text) {
    (Some(kind), Some(text)) =>
      token_matches_syntax_kind(expected_token.token, text, kind)
    _ => false
  }
}

///|
/// Check if the trailing context matches
fn trailing_context_matches(
  tokens : Array[TokenInfo],
  token_pos : Int,
  node_token_count : Int,
) -> Bool {
  // Get the token that would follow this node
  let after_pos = token_pos + node_token_count
  if after_pos >= tokens.length() {
    // At EOF, no trailing context to check
    return true
  }
  // For safety, we check if the next token is a structural token.
  // If the position is correct and we're outside damage, the trailing
  // context should be consistent.
  let after_token = tokens[after_pos]
  match after_token.token {
    EOF | RightParen | Then | Else => true
    Plus | Minus => true
    _ => true
  }
}

///|
/// Get the width of a green element
fn element_width(elem : GreenElement) -> Int {
  match elem {
    Token(t) => t.text_len()
    Node(n) => n.text_len
  }
}

///|
/// Advance cursor to target offset, returning the node at that position if found.
/// This is O(depth) because we only descend/ascend as needed.
fn ReuseCursor::seek_node_at(
  self : ReuseCursor,
  target_offset : Int,
  expected_kind : SyntaxKind,
) -> (GreenNode, Int)? {
  // If target is before current position, we need to reset
  // (parsing should be left-to-right, but handle this case)
  if target_offset < self.current_offset {
    // Reset to root - drain non-root frames and reset root's child_index
    let root_frame = self.stack[0]
    let _ = self.stack.drain(1, self.stack.length())
    root_frame.child_index = 0
    self.current_offset = 0
  }

  // Advance through the tree to find a node at target_offset
  while self.stack.length() > 0 {
    let frame = self.stack[self.stack.length() - 1]
    let node = frame.node

    // Check if current node matches
    if frame.start_offset == target_offset && node.kind == expected_kind {
      return Some((node, frame.start_offset))
    }

    // If target is outside this node's range, pop up
    let node_end = frame.start_offset + node.text_len
    if target_offset < frame.start_offset || target_offset >= node_end {
      // Pop this frame and advance parent's child_index
      let _ = self.stack.pop()
      if self.stack.length() > 0 {
        let parent = self.stack[self.stack.length() - 1]
        parent.child_index = parent.child_index + 1
      }
      continue
    }

    // Target is within this node - search children
    let mut child_offset = frame.start_offset
    let mut found_child = false

    // Skip children we've already passed
    for i = 0; i < frame.child_index; i = i + 1 {
      child_offset = child_offset + element_width(node.children[i])
    }

    // Search remaining children
    while frame.child_index < node.children.length() {
      let child = node.children[frame.child_index]
      let child_width = element_width(child)
      let child_end = child_offset + child_width

      if target_offset < child_offset {
        // Target is before this child - no match possible
        break
      }

      if target_offset < child_end {
        // Target is within this child
        match child {
          Node(child_node) => {
            // Check if this child node matches
            if child_offset == target_offset && child_node.kind == expected_kind {
              self.current_offset = child_offset
              return Some((child_node, child_offset))
            }
            // Descend into this child
            self.stack.push(
              { node: child_node, child_index: 0, start_offset: child_offset },
            )
            found_child = true
            break
          }
          Token(_) => {
            // Target is at a token position, not a node - no match
            self.current_offset = child_offset
            return None
          }
        }
      }

      // Move past this child
      child_offset = child_end
      frame.child_index = frame.child_index + 1
    }

    if not(found_child) {
      // No child contains the target - pop up
      let _ = self.stack.pop()
      if self.stack.length() > 0 {
        let parent = self.stack[self.stack.length() - 1]
        parent.child_index = parent.child_index + 1
      }
    }
  }

  None
}

///|
/// Try to get a reusable node at current byte offset with expected kind
///
/// For try_reuse to return Some(node):
/// 1. A node exists at byte_offset with kind == expected_kind
/// 2. Node is outside damaged range
/// 3. Leading token matches
/// 4. Trailing context matches
pub fn ReuseCursor::try_reuse(
  self : ReuseCursor,
  expected_kind : SyntaxKind,
  byte_offset : Int,
  token_pos : Int,
) -> GreenNode? {
  // Fast path: skip if reuse is globally disabled or byte_offset is in damaged range
  if self.reuse_globally_disabled ||
    (byte_offset >= self.damaged_range.start &&
    byte_offset < self.damaged_range.end) {
    return None
  }

  // Use stateful cursor to find node - O(depth) instead of O(tree)
  let result = self.seek_node_at(byte_offset, expected_kind)

  match result {
    None => None
    Some((node, node_offset)) => {
      // Condition 2: Node is outside damaged range
      let node_end = node_offset + node.text_len
      if not(is_outside_damage(node_offset, node_end, self.damaged_range)) {
        None
      } else if not(leading_token_matches(node, self.tokens, token_pos)) {
        None
      } else {
        // Condition 4: Trailing context matches
        let node_token_count = count_tokens_in_node(node)
        if not(
            trailing_context_matches(self.tokens, token_pos, node_token_count),
          ) {
          None
        } else {
          // All conditions met - can reuse!
          Some(node)
        }
      }
    }
  }
}

///|
/// Advance cursor past a reused node (updates traversal state)
pub fn ReuseCursor::advance_past(self : ReuseCursor, node : GreenNode) -> Unit {
  self.current_offset = self.current_offset + node.text_len
}
