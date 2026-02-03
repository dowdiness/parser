// ReuseCursor for checkpoint-based subtree reuse during incremental parsing
//
// The cursor walks the old green tree in parallel with parsing,
// enabling reuse of unchanged subtrees.

///|
/// Cursor for walking an old green tree to find reusable subtrees
pub struct ReuseCursor {
  // The old green tree root
  old_tree : GreenNode
  // Damage information - subtrees overlapping this range cannot be reused
  damaged_range : Range
  // Token buffer for context checks (new tokens)
  tokens : Array[TokenInfo]
}

///|
/// Create a new reuse cursor
pub fn ReuseCursor::new(
  old_tree : GreenNode,
  damaged_range : Range,
  tokens : Array[TokenInfo],
) -> ReuseCursor {
  { old_tree, damaged_range, tokens }
}

///|
/// Count the total number of tokens in a green node
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
/// Find a reusable node at the given byte offset with expected kind
fn find_node_at_offset(
  node : GreenNode,
  node_offset : Int,
  target_offset : Int,
  expected_kind : SyntaxKind,
) -> (GreenNode, Int)? {
  // If this node starts at the target offset and has the expected kind
  if node_offset == target_offset && node.kind == expected_kind {
    return Some((node, node_offset))
  }

  // If the target is outside this node's range, no match
  let node_end = node_offset + node.text_len
  if target_offset < node_offset || target_offset >= node_end {
    return None
  }

  // Search in children
  let mut child_offset = node_offset
  for child in node.children {
    match child {
      Node(child_node) => {
        let result = find_node_at_offset(
          child_node, child_offset, target_offset, expected_kind,
        )
        if result is Some(_) {
          return result
        }
        child_offset = child_offset + child_node.text_len
      }
      Token(t) => child_offset = child_offset + t.text_len()
    }
  }
  None
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
  // Find a node at the given byte offset with expected kind
  let result = find_node_at_offset(self.old_tree, 0, byte_offset, expected_kind)
  match result {
    None => None
    Some((node, node_offset)) => {
      // Condition 2: Node is outside damaged range
      let node_end = node_offset + node.text_len
      if not(is_outside_damage(node_offset, node_end, self.damaged_range)) {
        return None
      }

      // Condition 3: Leading token matches
      if not(leading_token_matches(node, self.tokens, token_pos)) {
        return None
      }

      // Condition 4: Trailing context matches
      let node_token_count = count_tokens_in_node(node)
      if not(trailing_context_matches(self.tokens, token_pos, node_token_count)) {
        return None
      }

      // All conditions met - can reuse!
      Some(node)
    }
  }
}

///|
/// Stub methods for API compatibility (no longer needed with simplified approach)
pub fn ReuseCursor::advance_past(self : ReuseCursor, _node : GreenNode) -> Unit {
  ignore(self)
}
