///|
/// Language-independent node kind (equivalent to rowan's RawSyntaxKind).
/// Each language defines its own enum and converts to/from RawKind via to_raw()/from_raw().
pub(all) struct RawKind(Int) derive(Eq, Show, Hash)

///|
pub(all) struct GreenToken {
  kind : RawKind
  text : String
  hash : Int
} derive(Show)

///|
/// Create a GreenToken. Hash is computed from kind and text.
pub fn GreenToken::new(kind : RawKind, text : String) -> GreenToken {
  let RawKind(k) = kind
  let h = combine_hash(k, string_hash(text))
  { kind, text, hash: h }
}

///|
pub fn GreenToken::text_len(self : GreenToken) -> Int {
  self.text.length()
}

///|
pub impl Eq for GreenToken with equal(self, other) {
  if self.hash != other.hash {
    return false
  }
  self.kind == other.kind && self.text == other.text
}

///|
pub(all) enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
} derive(Show)

///|
pub fn GreenElement::text_len(self : GreenElement) -> Int {
  match self {
    Token(t) => t.text_len()
    Node(n) => n.text_len
  }
}

///|
pub fn GreenElement::kind(self : GreenElement) -> RawKind {
  match self {
    Token(t) => t.kind
    Node(n) => n.kind
  }
}

///|
pub impl Eq for GreenElement with equal(self, other) {
  match (self, other) {
    (Token(a), Token(b)) => a == b
    (Node(a), Node(b)) => a == b
    _ => false
  }
}

///|
pub(all) struct GreenNode {
  kind : RawKind
  children : Array[GreenElement]
  text_len : Int
  hash : Int
} derive(Show)

///|
/// Create a GreenNode. text_len and hash are computed from children.
pub fn GreenNode::new(
  kind : RawKind,
  children : Array[GreenElement],
) -> GreenNode {
  let RawKind(k) = kind
  let mut text_len = 0
  let mut h = k
  for child in children {
    text_len = text_len + child.text_len()
    h = combine_hash(h, child_hash(child))
  }
  { kind, children, text_len, hash: h }
}

///|
fn child_hash(elem : GreenElement) -> Int {
  match elem {
    Token(t) => t.hash
    Node(n) => n.hash
  }
}

///|
pub fn GreenNode::kind(self : GreenNode) -> RawKind {
  self.kind
}

///|
pub impl Eq for GreenNode with equal(self, other) {
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
/// Check if this green tree contains any error nodes or error tokens.
/// error_node_kind and error_token_kind are language-specific RawKind values.
pub fn GreenNode::has_errors(
  self : GreenNode,
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
