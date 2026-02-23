///|
test "RawKind equality" {
  let a = RawKind(5)
  let b = RawKind(5)
  let c = RawKind(6)
  inspect(a == b, content="true")
  inspect(a == c, content="false")
}

///|
test "GreenToken constructor computes hash" {
  let t = GreenToken::new(RawKind(9), "hello")
  inspect(t.text, content="hello")
  inspect(t.kind == RawKind(9), content="true")
  // Hash is nonzero
  inspect(t.hash != 0, content="true")
}

///|
test "GreenToken Eq is hash-based fast path" {
  let a = GreenToken::new(RawKind(9), "x")
  let b = GreenToken::new(RawKind(9), "x")
  let c = GreenToken::new(RawKind(9), "y")
  inspect(a == b, content="true")
  inspect(a == c, content="false")
}

///|
test "GreenToken text_len" {
  let t = GreenToken::new(RawKind(9), "hello")
  inspect(t.text_len(), content="5")
}

///|
test "GreenNode constructor computes text_len and hash" {
  let tok = GreenToken::new(RawKind(9), "x")
  let elem = GreenElement::Token(tok)
  let node = GreenNode::new(RawKind(20), [elem])
  inspect(node.text_len, content="1")
  inspect(node.hash != 0, content="true")
}

///|
test "GreenNode Eq: identical nodes are equal" {
  let a = GreenNode::new(RawKind(0), [])
  let b = GreenNode::new(RawKind(0), [])
  inspect(a == b, content="true")
}

///|
test "GreenNode Eq: different kind not equal" {
  let a = GreenNode::new(RawKind(0), [])
  let b = GreenNode::new(RawKind(1), [])
  inspect(a == b, content="false")
}

///|
test "GreenElement text_len and kind" {
  let tok = GreenToken::new(RawKind(9), "hello")
  let elem = GreenElement::Token(tok)
  inspect(elem.text_len(), content="5")
  inspect(elem.kind() == RawKind(9), content="true")
}

///|
test "GreenNode token_count: no trivia_kind counts all leaf tokens" {
  let ws_tok = GreenToken::new(RawKind(11), " ")
  let id_tok = GreenToken::new(RawKind(9), "x")
  let node = GreenNode::new(RawKind(20), [
    GreenElement::Token(id_tok),
    GreenElement::Token(ws_tok),
  ])
  inspect(node.token_count, content="2")
}

///|
test "GreenNode token_count: trivia_kind excludes whitespace" {
  let ws_kind = RawKind(11)
  let ws_tok = GreenToken::new(ws_kind, " ")
  let id_tok = GreenToken::new(RawKind(9), "x")
  let node = GreenNode::new(
    RawKind(20),
    [GreenElement::Token(id_tok), GreenElement::Token(ws_tok)],
    trivia_kind=Some(ws_kind),
  )
  inspect(node.token_count, content="1")
}

///|
test "GreenNode token_count: propagates through sub-nodes" {
  let ws_kind = RawKind(11)
  let ws_tok = GreenToken::new(ws_kind, " ")
  let id_tok = GreenToken::new(RawKind(9), "x")
  let int_tok = GreenToken::new(RawKind(10), "1")
  let inner = GreenNode::new(
    RawKind(19),
    [GreenElement::Token(int_tok)],
    trivia_kind=Some(ws_kind),
  )
  let root = GreenNode::new(
    RawKind(16),
    [
      GreenElement::Token(id_tok),
      GreenElement::Token(ws_tok),
      GreenElement::Node(inner),
    ],
    trivia_kind=Some(ws_kind),
  )
  // id_tok (1) + ws_tok (excluded) + inner.token_count (1) = 2
  inspect(root.token_count, content="2")
}

///|
test "has_errors detects error node kind" {
  let error_node_kind = RawKind(21)
  let error_token_kind = RawKind(12)
  let err = GreenNode::new(error_node_kind, [])
  inspect(err.has_errors(error_node_kind, error_token_kind), content="true")
}

///|
test "has_errors returns false for clean node" {
  let error_node_kind = RawKind(21)
  let error_token_kind = RawKind(12)
  let clean = GreenNode::new(RawKind(22), [])
  inspect(clean.has_errors(error_node_kind, error_token_kind), content="false")
}
