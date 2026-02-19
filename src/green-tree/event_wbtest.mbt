///|
test "build_tree: single token produces root node" {
  let events = [ParseEvent::Token(RawKind(10), "42")]
  let root = build_tree(events, RawKind(22))
  inspect(root.kind == RawKind(22), content="true")
  inspect(root.children.length(), content="1")
  inspect(root.text_len, content="2")
}

///|
test "build_tree: nested StartNode/FinishNode" {
  let events = [
    ParseEvent::StartNode(RawKind(19)), // IntLiteral
    ParseEvent::Token(RawKind(10), "5"),
    ParseEvent::FinishNode,
  ]
  let root = build_tree(events, RawKind(22))
  inspect(root.kind == RawKind(22), content="true")
  inspect(root.children.length(), content="1")
  let child = match root.children[0] {
    GreenElement::Node(n) => n
    GreenElement::Token(_) => abort("expected node")
  }
  inspect(child.kind == RawKind(19), content="true")
  inspect(child.text_len, content="1")
}

///|
test "EventBuffer mark and start_at" {
  let buf = EventBuffer::new()
  let m = buf.mark()
  buf.push(ParseEvent::Token(RawKind(9), "x"))
  buf.start_at(m, RawKind(20)) // retroactively set mark to VarRef
  inspect(buf.events[m] == ParseEvent::StartNode(RawKind(20)), content="true")
}

///|
test "Tombstone events are ignored by build_tree" {
  let events = [ParseEvent::Tombstone, ParseEvent::Token(RawKind(10), "1")]
  let root = build_tree(events, RawKind(22))
  inspect(root.children.length(), content="1")
}

///|
test "panic EventBuffer::start_at rejects out-of-bounds mark" {
  let buf = EventBuffer::new()
  buf.start_at(0, RawKind(20))
}

///|
test "panic EventBuffer::start_at rejects non-Tombstone mark" {
  let buf = EventBuffer::new()
  buf.push(ParseEvent::Token(RawKind(9), "x"))
  buf.start_at(0, RawKind(20))
}

///|
test "panic build_tree: missing FinishNode aborts" {
  ignore(
    build_tree(
      [ParseEvent::StartNode(RawKind(19)), ParseEvent::Token(RawKind(10), "5")],
      RawKind(22),
    ),
  )
}
