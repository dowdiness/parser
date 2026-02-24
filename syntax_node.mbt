///|
pub struct SyntaxNode {
  cst : CstNode
  parent : SyntaxNode?
  offset : Int
}

///|
pub fn SyntaxNode::new(
  cst : CstNode,
  parent : SyntaxNode?,
  offset : Int,
) -> SyntaxNode {
  { cst, parent, offset }
}

///|
/// Create a root SyntaxNode from a CstNode (offset = 0, no parent).
pub fn SyntaxNode::from_cst(cst : CstNode) -> SyntaxNode {
  SyntaxNode::new(cst, None, 0)
}

///|
pub fn SyntaxNode::start(self : SyntaxNode) -> Int {
  self.offset
}

///|
pub fn SyntaxNode::end(self : SyntaxNode) -> Int {
  self.offset + self.cst.text_len
}

///|
pub fn SyntaxNode::kind(self : SyntaxNode) -> RawKind {
  self.cst.kind
}

///|
pub fn SyntaxNode::children(self : SyntaxNode) -> Array[SyntaxNode] {
  let result : Array[SyntaxNode] = []
  for offset = self.offset, i = 0; i < self.cst.children.length(); {
    match self.cst.children[i] {
      Node(cst_child) => {
        result.push(SyntaxNode::new(cst_child, Some(self), offset))
        continue offset + cst_child.text_len, i + 1
      }
      Token(token) => continue offset + token.text_len(), i + 1
    }
  }
  result
}
