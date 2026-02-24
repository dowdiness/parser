///|
pub struct SyntaxNode {
  green : CstNode
  parent : SyntaxNode?
  offset : Int
}

///|
pub fn SyntaxNode::new(
  green : CstNode,
  parent : SyntaxNode?,
  offset : Int,
) -> SyntaxNode {
  { green, parent, offset }
}

///|
/// Create a root SyntaxNode from a CstNode (offset = 0, no parent).
pub fn SyntaxNode::from_green(green : CstNode) -> SyntaxNode {
  SyntaxNode::new(green, None, 0)
}

///|
pub fn SyntaxNode::start(self : SyntaxNode) -> Int {
  self.offset
}

///|
pub fn SyntaxNode::end(self : SyntaxNode) -> Int {
  self.offset + self.green.text_len
}

///|
pub fn SyntaxNode::kind(self : SyntaxNode) -> RawKind {
  self.green.kind
}

///|
pub fn SyntaxNode::children(self : SyntaxNode) -> Array[SyntaxNode] {
  let result : Array[SyntaxNode] = []
  for offset = self.offset, i = 0; i < self.green.children.length(); {
    match self.green.children[i] {
      Node(green_child) => {
        result.push(SyntaxNode::new(green_child, Some(self), offset))
        continue offset + green_child.text_len, i + 1
      }
      Token(token) => continue offset + token.text_len(), i + 1
    }
  }
  result
}
