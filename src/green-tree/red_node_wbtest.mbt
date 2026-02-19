///|
test "RedNode::from_green creates root at offset 0" {
  let green = GreenNode::new(RawKind(22), [])
  let red = RedNode::from_green(green)
  inspect(red.start(), content="0")
  inspect(red.end(), content="0")
  inspect(red.kind() == RawKind(22), content="true")
}

///|
test "RedNode::children computes offsets" {
  // Build: SourceFile containing a GreenToken "hello"
  let tok = GreenToken::new(RawKind(9), "hello")
  let child_elem = GreenElement::Token(tok)
  let inner = GreenNode::new(RawKind(20), [child_elem])
  let root = GreenNode::new(RawKind(22), [GreenElement::Node(inner)])
  let red = RedNode::from_green(root)
  let children = red.children()
  inspect(children.length(), content="1")
  inspect(children[0].start(), content="0")
  inspect(children[0].end(), content="5")
}
