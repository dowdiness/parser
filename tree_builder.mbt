///|
pub struct TreeBuilder(Array[Array[GreenElement]])

///|
pub fn TreeBuilder::new() -> TreeBuilder {
  TreeBuilder([[]])
}

///|
pub fn TreeBuilder::start_node(self : TreeBuilder, kind : SyntaxKind) -> Unit {
  let _ = kind
  self.0.push([])
}

///|
pub fn TreeBuilder::finish_node(self : TreeBuilder, kind : SyntaxKind) -> Unit {
  let children = self.0.pop().unwrap()
  let node = GreenNode::new(kind, children)
  self.0.last().unwrap().push(Node(node))
}

///|
pub fn TreeBuilder::token(
  self : TreeBuilder,
  kind : SyntaxKind,
  text : String,
) -> Unit {
  let token = GreenToken::new(kind, text)
  self.0.last().unwrap().push(Token(token))
}

///|
pub fn TreeBuilder::finish(self : TreeBuilder) -> GreenNode {
  let children = self.0.pop().unwrap()
  GreenNode::new(SourceFile, children)
}
