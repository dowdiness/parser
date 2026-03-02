///|
test "NodeInterner: intern_node returns structurally equal node" {
  let ni = NodeInterner::new()
  let node = CstNode::new(RawKind(1), [])
  let result = ni.intern_node(node)
  inspect(result == node, content="true")
}

///|
test "NodeInterner: second call for equal structure does not grow size" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  let _ = ni.intern_node(CstNode::new(RawKind(1), [])) // structurally equal
  inspect(ni.size(), content="1")
}

///|
test "NodeInterner: distinct structures get distinct entries" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  let _ = ni.intern_node(CstNode::new(RawKind(2), []))
  inspect(ni.size(), content="2")
}

///|
test "NodeInterner: clear resets size to zero" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  inspect(ni.size(), content="1")
  ni.clear()
  inspect(ni.size(), content="0")
}

///|
test "NodeInterner: intern works correctly after clear" {
  let ni = NodeInterner::new()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  ni.clear()
  let _ = ni.intern_node(CstNode::new(RawKind(1), []))
  inspect(ni.size(), content="1")
}

///|
test "NodeInterner: parent with interned children deduplicates" {
  let ni = NodeInterner::new()
  let child = ni.intern_node(CstNode::new(RawKind(1), []))
  let p1 = CstNode::new(RawKind(2), [Node(child)])
  let p2 = CstNode::new(RawKind(2), [Node(child)])
  let _ = ni.intern_node(p1)
  let _ = ni.intern_node(p2)
  inspect(ni.size(), content="2") // child + parent, no duplicate parent
}
