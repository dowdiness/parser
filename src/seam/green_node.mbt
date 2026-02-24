///|
/// Language-independent node kind (equivalent to rowan's RawSyntaxKind).
/// Each language defines its own enum and converts to/from RawKind via to_raw()/from_raw().
pub(all) struct RawKind(Int) derive(Eq, Show, Hash, Compare)

///|
pub(all) struct CstToken {
  kind : RawKind
  text : String
  hash : Int
} derive(Show)

///|
/// Create a CstToken. Hash is computed from kind and text.
pub fn CstToken::new(kind : RawKind, text : String) -> CstToken {
  let RawKind(k) = kind
  let h = combine_hash(k, string_hash(text))
  { kind, text, hash: h }
}

///|
pub fn CstToken::text_len(self : CstToken) -> Int {
  self.text.length()
}

///|
pub impl Eq for CstToken with equal(self, other) {
  if self.hash != other.hash {
    return false
  }
  self.kind == other.kind && self.text == other.text
}

///|
/// Hash implementation reuses the cached structural hash.
pub impl Hash for CstToken with hash_combine(self, hasher) {
  hasher.combine_int(self.hash)
}

///|
pub(all) enum CstElement {
  Token(CstToken)
  Node(CstNode)
} derive(Show)

///|
pub fn CstElement::text_len(self : CstElement) -> Int {
  match self {
    Token(t) => t.text_len()
    Node(n) => n.text_len
  }
}

///|
pub fn CstElement::kind(self : CstElement) -> RawKind {
  match self {
    Token(t) => t.kind
    Node(n) => n.kind
  }
}

///|
pub impl Eq for CstElement with equal(self, other) {
  match (self, other) {
    (Token(a), Token(b)) => a == b
    (Node(a), Node(b)) => a == b
    _ => false
  }
}

///|
/// Include a variant tag to reduce cross-variant collisions.
/// This is intentionally different from child_hash():
/// - child_hash() is used only for internal cached structural hashing in CstNode::new
/// - Hash trait output adds a variant tag for safer external hash-table usage
pub impl Hash for CstElement with hash_combine(self, hasher) {
  let h = match self {
    Token(t) => combine_hash(1, t.hash)
    Node(n) => combine_hash(2, n.hash)
  }
  hasher.combine_int(h)
}

///|
pub(all) struct CstNode {
  kind : RawKind
  children : Array[CstElement]
  text_len : Int
  hash : Int
  /// Non-trivia leaf token count. Equals the number of leaf tokens whose kind
  /// is NOT equal to `trivia_kind` (when provided to `CstNode::new`).
  /// Equals the total leaf token count when no `trivia_kind` is given.
  /// Used by the incremental parser to advance `position` (whitespace-free
  /// token index) without an O(subtree) traversal on every reuse.
  token_count : Int
} derive(Show)

///|
/// Create a CstNode. text_len, hash, and token_count are computed from children.
///
/// `trivia_kind`: when provided, leaf tokens with this kind are excluded from
/// `token_count`.  Pass `Some(whitespace_raw_kind)` from the language layer to
/// get a non-whitespace token count.  Pass nothing (or `None`) for a
/// language-agnostic total leaf token count.
pub fn CstNode::new(
  kind : RawKind,
  children : Array[CstElement],
  trivia_kind? : RawKind? = None,
) -> CstNode {
  let RawKind(k) = kind
  let mut text_len = 0
  let mut h = k
  let mut token_count = 0
  for child in children {
    text_len = text_len + child.text_len()
    h = combine_hash(h, child_hash(child))
    match child {
      Token(t) =>
        match trivia_kind {
          Some(ws) => if t.kind != ws { token_count = token_count + 1 }
          None => token_count = token_count + 1
        }
      Node(n) => token_count = token_count + n.token_count
    }
  }
  { kind, children, text_len, hash: h, token_count }
}

///|
fn child_hash(elem : CstElement) -> Int {
  match elem {
    Token(t) => t.hash
    Node(n) => n.hash
  }
}

///|
pub fn CstNode::kind(self : CstNode) -> RawKind {
  self.kind
}

///|
pub impl Eq for CstNode with equal(self, other) {
  if self.hash != other.hash {
    return false
  }
  if self.kind != other.kind ||
    self.children.length() != other.children.length() {
    return false
  }
  for i = 0; i < self.children.length(); i = i + 1 {
    if self.children[i] != other.children[i] {
      return false
    }
  }
  true
}

///|
/// Hash implementation reuses the cached structural hash.
pub impl Hash for CstNode with hash_combine(self, hasher) {
  hasher.combine_int(self.hash)
}

///|
/// Check if this green tree contains any error nodes or error tokens.
/// error_node_kind and error_token_kind are language-specific RawKind values.
pub fn CstNode::has_errors(
  self : CstNode,
  error_node_kind : RawKind,
  error_token_kind : RawKind,
) -> Bool {
  if self.kind == error_node_kind {
    return true
  }
  for elem in self.children {
    match elem {
      Token(t) => if t.kind == error_token_kind { return true }
      Node(n) =>
        if n.has_errors(error_node_kind, error_token_kind) {
          return true
        }
    }
  }
  false
}
