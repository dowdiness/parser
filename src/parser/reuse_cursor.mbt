// ReuseCursor for checkpoint-based subtree reuse during incremental parsing
//
// The cursor walks the old green tree in parallel with parsing,
// enabling reuse of unchanged subtrees. Uses a stateful traversal
// to achieve O(depth) lookup instead of O(tree).

///|
/// Frame in the cursor stack, tracking position within a node
struct CursorFrame {
  node : @green_tree.GreenNode
  mut child_index : Int
  start_offset : Int // Byte offset where this node starts
}

///|
/// Flattened non-whitespace token from the old green tree.
struct OldToken {
  kind : @green_tree.RawKind
  text : String
  start : Int
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
  damaged_range : @range.Range
  // Token buffer for context checks (new tokens)
  tokens : Array[@token.TokenInfo]
  // Flattened non-whitespace tokens from old tree for follow-token checks
  old_tokens : Array[OldToken]
  // Fast path: true if damage covers root (no reuse possible)
  reuse_globally_disabled : Bool
}

///|
fn collect_old_tokens(
  node : @green_tree.GreenNode,
  node_start : Int,
  out : Array[OldToken],
) -> Unit {
  let mut offset = node_start
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) => {
        if t.kind != @syntax.WhitespaceToken.to_raw() {
          out.push({ kind: t.kind, text: t.text, start: offset })
        }
        offset = offset + t.text_len()
      }
      @green_tree.GreenElement::Node(n) => {
        collect_old_tokens(n, offset, out)
        offset = offset + n.text_len
      }
    }
  }
}

///|
/// Create a new reuse cursor positioned at the start of the tree
pub fn ReuseCursor::new(
  old_tree : @green_tree.GreenNode,
  damaged_range : @range.Range,
  tokens : Array[@token.TokenInfo],
) -> ReuseCursor {
  // Disable reuse globally if damage covers the entire tree.
  // When damage spans [0, tree_len), no subtree can be outside damage.
  let reuse_globally_disabled = damaged_range.start <= 0 &&
    damaged_range.end >= old_tree.text_len
  let old_tokens : Array[OldToken] = []
  if not(reuse_globally_disabled) {
    collect_old_tokens(old_tree, 0, old_tokens)
  }
  let stack = [{ node: old_tree, child_index: 0, start_offset: 0 }]
  {
    stack,
    current_offset: 0,
    damaged_range,
    tokens,
    old_tokens,
    reuse_globally_disabled,
  }
}

///|
/// Get the old tree root (for testing/debugging)
pub fn ReuseCursor::old_tree(self : ReuseCursor) -> @green_tree.GreenNode {
  self.stack[0].node
}

///|
/// Check if reuse is globally disabled (damage covers entire tree)
pub fn ReuseCursor::is_reuse_disabled(self : ReuseCursor) -> Bool {
  self.reuse_globally_disabled
}

///|
/// Count the total number of non-whitespace tokens in a green node
fn count_tokens_in_node(node : @green_tree.GreenNode) -> Int {
  let mut count = 0
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() {
          count = count + 1
        }
      @green_tree.GreenElement::Node(n) =>
        count = count + count_tokens_in_node(n)
    }
  }
  count
}

///|
/// Get the first non-whitespace token text from a green node
fn first_token_text(node : @green_tree.GreenNode) -> String? {
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() {
          return Some(t.text)
        }
      @green_tree.GreenElement::Node(n) => {
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
fn first_token_kind(node : @green_tree.GreenNode) -> @green_tree.RawKind? {
  for child in node.children {
    match child {
      @green_tree.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() {
          return Some(t.kind)
        }
      @green_tree.GreenElement::Node(n) => {
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
/// Map RawKind to the corresponding Token for comparison
fn syntax_kind_to_token_kind(kind : @green_tree.RawKind) -> @token.Token? {
  match @syntax.SyntaxKind::from_raw(kind) {
    @syntax.LambdaToken => Some(@token.Lambda)
    @syntax.DotToken => Some(@token.Dot)
    @syntax.LeftParenToken => Some(@token.LeftParen)
    @syntax.RightParenToken => Some(@token.RightParen)
    @syntax.PlusToken => Some(@token.Plus)
    @syntax.MinusToken => Some(@token.Minus)
    @syntax.IfKeyword => Some(@token.If)
    @syntax.ThenKeyword => Some(@token.Then)
    @syntax.ElseKeyword => Some(@token.Else)
    _ => None
  }
}

///|
/// Check if a syntax kind matches a token (for leading token check)
fn token_matches_syntax_kind(
  token : @token.Token,
  text : String,
  kind : @green_tree.RawKind,
) -> Bool {
  match @syntax.SyntaxKind::from_raw(kind) {
    @syntax.IdentToken =>
      match token {
        @token.Identifier(name) => name == text
        _ => false
      }
    @syntax.IntToken =>
      match token {
        // Require numeric value and canonical text to match.
        // This prevents false positives where any integer kind would pass.
        @token.Integer(value) => {
          let parsed = @strconv.parse_int(text) catch { _ => return false }
          parsed == value && value.to_string() == text
        }
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
  damaged_range : @range.Range,
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
  node : @green_tree.GreenNode,
  tokens : Array[@token.TokenInfo],
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
/// Find the first old non-whitespace token with start >= offset.
fn old_follow_token(old_tokens : Array[OldToken], offset : Int) -> OldToken? {
  let mut lo = 0
  let mut hi = old_tokens.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if old_tokens[mid].start < offset {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < old_tokens.length() { Some(old_tokens[lo]) } else { None }
}

///|
/// Compare follow token from old tree and new token stream.
/// Option B: follow-token equality must hold for reuse.
fn trailing_context_matches(
  old_tokens : Array[OldToken],
  tokens : Array[@token.TokenInfo],
  node_end : Int,
  token_pos : Int,
  node_token_count : Int,
) -> Bool {
  // Note: node_end is in old-source coordinates. For a node outside the
  // damaged range, its boundary byte offset is unchanged in the new source,
  // so the old follow token and the new token at after_pos represent the
  // same source boundary.
  let after_pos = token_pos + node_token_count
  let old_follow = old_follow_token(old_tokens, node_end)
  let new_follow = if after_pos < tokens.length() {
    match tokens[after_pos].token {
      @token.EOF => None
      _ => Some(tokens[after_pos])
    }
  } else {
    None
  }
  match (old_follow, new_follow) {
    (None, None) => true
    (Some(old), Some(new_info)) =>
      token_matches_syntax_kind(new_info.token, old.text, old.kind)
    _ => false
  }
}

///|
/// Get the width of a green element
fn element_width(elem : @green_tree.GreenElement) -> Int {
  match elem {
    @green_tree.GreenElement::Token(t) => t.text_len()
    @green_tree.GreenElement::Node(n) => n.text_len
  }
}

///|
/// Advance cursor to target offset, returning the node at that position if found.
/// This is O(depth) because we only descend/ascend as needed.
fn ReuseCursor::seek_node_at(
  self : ReuseCursor,
  target_offset : Int,
  expected_kind : @green_tree.RawKind,
) -> (@green_tree.GreenNode, Int)? {
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
          @green_tree.GreenElement::Node(child_node) => {
            // Check if this child node matches
            if child_offset == target_offset && child_node.kind == expected_kind {
              self.current_offset = child_offset
              return Some((child_node, child_offset))
            }
            // Descend into this child
            self.stack.push({
              node: child_node,
              child_index: 0,
              start_offset: child_offset,
            })
            found_child = true
            break
          }
          @green_tree.GreenElement::Token(_) => {
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
  expected_kind : @green_tree.RawKind,
  byte_offset : Int,
  token_pos : Int,
) -> @green_tree.GreenNode? {
  // Fast path: skip if reuse is globally disabled or byte_offset is in damaged range
  if self.reuse_globally_disabled ||
    (
      byte_offset >= self.damaged_range.start &&
      byte_offset < self.damaged_range.end
    ) {
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
            trailing_context_matches(
              self.old_tokens,
              self.tokens,
              node_end,
              token_pos,
              node_token_count,
            ),
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
pub fn ReuseCursor::advance_past(
  self : ReuseCursor,
  node : @green_tree.GreenNode,
) -> Unit {
  self.current_offset = self.current_offset + node.text_len
}
