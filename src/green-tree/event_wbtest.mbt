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

///|
test "panic build_tree: leading FinishNode aborts" {
  ignore(build_tree([ParseEvent::FinishNode], RawKind(22)))
}

///|
test "panic build_tree: extra FinishNode aborts" {
  ignore(
    build_tree(
      [
        ParseEvent::StartNode(RawKind(19)),
        ParseEvent::Token(RawKind(10), "5"),
        ParseEvent::FinishNode,
        ParseEvent::FinishNode,
      ],
      RawKind(22),
    ),
  )
}

///|
test "build_tree_interned: structurally equal to build_tree" {
  let root_kind = RawKind(0)
  let node_kind = RawKind(1)
  let tok_kind = RawKind(2)
  let events1 = [
    ParseEvent::StartNode(node_kind),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::FinishNode,
  ]
  let events2 = [
    ParseEvent::StartNode(node_kind),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::Token(tok_kind, "x"),
    ParseEvent::FinishNode,
  ]
  let plain = build_tree(events1, root_kind)
  let interner = Interner::new()
  let interned = build_tree_interned(events2, root_kind, interner)
  inspect(plain == interned, content="true")
}

///|
test "build_tree_interned: interner size bounded by vocabulary" {
  let root_kind = RawKind(0)
  let tok_kind = RawKind(1)
  let interner = Interner::new()
  let events : Array[ParseEvent] = []
  for _ in 0..<100 {
    events.push(ParseEvent::Token(tok_kind, "x"))
  }
  let _ = build_tree_interned(events, root_kind, interner)
  inspect(interner.size(), content="1")
}
