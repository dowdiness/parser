///|
test "SyntaxNode::from_cst creates root at offset 0" {
  let cst = CstNode::new(RawKind(22), [])
  let syntax = SyntaxNode::from_cst(cst)
  inspect(syntax.start(), content="0")
  inspect(syntax.end(), content="0")
  inspect(syntax.kind() == RawKind(22), content="true")
}

///|
test "SyntaxNode::children computes offsets" {
  // Build: SourceFile containing a CstToken "hello"
  let tok = CstToken::new(RawKind(9), "hello")
  let child_elem = CstElement::Token(tok)
  let inner = CstNode::new(RawKind(20), [child_elem])
  let root = CstNode::new(RawKind(22), [CstElement::Node(inner)])
  let syntax = SyntaxNode::from_cst(root)
  let children = syntax.children()
  inspect(children.length(), content="1")
  inspect(children[0].start(), content="0")
  inspect(children[0].end(), content="5")
}
