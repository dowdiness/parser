///|
pub struct RedNode {
  green : GreenNode
  parent : RedNode?
  offset : Int
}

///|
pub fn RedNode::new(
  green : GreenNode,
  parent : RedNode?,
  offset : Int,
) -> RedNode {
  { green, parent, offset }
}

///|
/// Create a root RedNode from a GreenNode (offset = 0, no parent).
pub fn RedNode::from_green(green : GreenNode) -> RedNode {
  RedNode::new(green, None, 0)
}

///|
pub fn RedNode::start(self : RedNode) -> Int {
  self.offset
}

///|
pub fn RedNode::end(self : RedNode) -> Int {
  self.offset + self.green.text_len
}

///|
pub fn RedNode::kind(self : RedNode) -> RawKind {
  self.green.kind
}

///|
pub fn RedNode::children(self : RedNode) -> Array[RedNode] {
  let result : Array[RedNode] = []
  for offset = self.offset, i = 0; i < self.green.children.length(); {
    match self.green.children[i] {
      Node(green_child) => {
        result.push(RedNode::new(green_child, Some(self), offset))
        continue offset + green_child.text_len, i + 1
      }
      Token(token) => continue offset + token.text_len(), i + 1
    }
  }
  result
}
