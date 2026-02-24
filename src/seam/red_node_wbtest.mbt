///|
test "SyntaxNode::from_green creates root at offset 0" {
  let green = CstNode::new(RawKind(22), [])
  let red = SyntaxNode::from_green(green)
  inspect(red.start(), content="0")
  inspect(red.end(), content="0")
  inspect(red.kind() == RawKind(22), content="true")
}

///|
test "SyntaxNode::children computes offsets" {
  // Build: SourceFile containing a CstToken "hello"
  let tok = CstToken::new(RawKind(9), "hello")
  let child_elem = CstElement::Token(tok)
  let inner = CstNode::new(RawKind(20), [child_elem])
  let root = CstNode::new(RawKind(22), [CstElement::Node(inner)])
  let red = SyntaxNode::from_green(root)
  let children = red.children()
  inspect(children.length(), content="1")
  inspect(children[0].start(), content="0")
  inspect(children[0].end(), content="5")
}
