///|
fn extract_token_text(green : GreenNode, token_kind : SyntaxKind) -> String? {
  for elem in green.children {
    match elem {
      Token(t) => if t.kind == token_kind { return Some(t.text) }
      _ => continue
    }
  }
  None
}

///|
/// Compute tight start/end positions for a green node, skipping leading and
/// trailing whitespace tokens. Returns (start, end) relative to the given offset.
fn tight_span(green : GreenNode, offset : Int) -> (Int, Int) {
  let mut pos = offset
  let mut tight_start = offset
  let mut tight_end = offset + green.text_len
  let mut found_start = false
  for elem in green.children {
    let len = elem.text_len()
    match elem {
      Token(t) =>
        if t.kind != WhitespaceToken {
          if not(found_start) {
            tight_start = pos
            found_start = true
          }
          tight_end = pos + len
        }
      Node(_) => {
        if not(found_start) {
          tight_start = pos
          found_start = true
        }
        tight_end = pos + len
      }
    }
    pos = pos + len
  }
  (tight_start, tight_end)
}

///|
fn find_child_nodes(green : GreenNode) -> Array[GreenNode] {
  let nodes : Array[GreenNode] = []
  for elem in green.children {
    match elem {
      Node(n) => nodes.push(n)
      Token(_) => continue
    }
  }
  nodes
}

///|
fn collect_binary_ops(green : GreenNode) -> Array[Bop] {
  let ops : Array[Bop] = []
  for elem in green.children {
    match elem {
      Token(t) =>
        match t.kind {
          PlusToken => ops.push(Bop::Plus)
          MinusToken => ops.push(Bop::Minus)
          _ => ()
        }
      _ => ()
    }
  }
  ops
}

///|
/// Convert a RedNode to a TermNode. Uses RedNode's offset-based position
/// computation instead of manual offset tracking.
fn convert_red(red : RedNode, counter : Ref[Int]) -> TermNode {
  fn next_id() -> Int {
    let id = counter.val
    counter.val = id + 1
    id
  }

  let g = red.green
  let off = red.start()
  match g.kind {
    IntLiteral => {
      let text = extract_token_text(g, IntToken).unwrap_or("")
      let value = @strconv.parse_int(text) catch { _ => 0 }
      let (tight_start, tight_end) = tight_span(g, off)
      TermNode::new(TermKind::Int(value), tight_start, tight_end, next_id(), [])
    }
    VarRef => {
      let name = extract_token_text(g, IdentToken).unwrap_or("")
      let (tight_start, tight_end) = tight_span(g, off)
      TermNode::new(TermKind::Var(name), tight_start, tight_end, next_id(), [])
    }
    LambdaExpr => {
      let param = extract_token_text(g, IdentToken).unwrap_or("")
      let (tight_start, tight_end) = tight_span(g, off)
      let red_children = red.children()
      for child in red_children {
        let body = convert_red(child, counter)
        return TermNode::new(
          TermKind::Lam(param),
          tight_start,
          body.end,
          next_id(),
          [body],
        )
      }
      TermNode::new(TermKind::Lam(param), tight_start, tight_end, next_id(), [])
    }
    AppExpr => {
      let children : Array[TermNode] = []
      let red_children = red.children()
      for child in red_children {
        children.push(convert_red(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          result = TermNode::new(
            TermKind::App,
            result.start,
            children[i].end,
            next_id(),
            [result, children[i]],
          )
        }
        result
      } else if children.length() == 1 {
        children[0]
      } else {
        TermNode::error("Empty AppExpr", off, next_id())
      }
    }
    BinaryExpr => {
      let ops = collect_binary_ops(g)
      let children : Array[TermNode] = []
      let red_children = red.children()
      for child in red_children {
        children.push(convert_red(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() { ops[i - 1] } else { Bop::Plus }
          result = TermNode::new(
            TermKind::Bop(op),
            result.start,
            children[i].end,
            next_id(),
            [result, children[i]],
          )
        }
        result
      } else if children.length() == 1 {
        children[0]
      } else {
        TermNode::error("Empty BinaryExpr", off, next_id())
      }
    }
    IfExpr => {
      let (tight_start, _) = tight_span(g, off)
      let children : Array[TermNode] = []
      let red_children = red.children()
      for child in red_children {
        children.push(convert_red(child, counter))
      }
      let if_end = if children.length() > 0 {
        children[children.length() - 1].end
      } else {
        off + g.text_len
      }
      TermNode::new(TermKind::If, tight_start, if_end, next_id(), children)
    }
    ParenExpr => {
      let (tight_start, tight_end) = tight_span(g, off)
      let red_children = red.children()
      for child in red_children {
        let inner = convert_red(child, counter)
        return TermNode::new(
          inner.kind,
          tight_start,
          tight_end,
          next_id(),
          inner.children,
        )
      }
      TermNode::error("Empty ParenExpr", off, next_id())
    }
    SourceFile => {
      let child_nodes = find_child_nodes(g)
      if child_nodes.length() > 0 {
        let red_children = red.children()
        for child in red_children {
          return convert_red(child, counter)
        }
      }
      TermNode::error("Empty SourceFile", off, next_id())
    }
    _ =>
      TermNode::error(
        "Unexpected node kind: " + g.kind.to_string(),
        off,
        next_id(),
      )
  }
}

///|
/// Convert a RedNode (position-aware CST facade) to a TermNode.
pub fn red_to_term_node(red : RedNode, node_id_counter : Ref[Int]) -> TermNode {
  convert_red(red, node_id_counter)
}

///|
/// Convert a GreenNode to a TermNode. Preserved for backward compatibility.
/// Internally creates a RedNode and delegates to convert_red.
pub fn green_to_term_node(
  green : GreenNode,
  offset : Int,
  node_id_counter : Ref[Int],
) -> TermNode {
  let red = RedNode::new(green, None, offset)
  convert_red(red, node_id_counter)
}

///|
pub fn green_to_term(green : GreenNode) -> Term {
  let node = green_to_term_node(green, 0, Ref::new(0))
  node_to_term(node)
}

///|
pub fn parse_green_to_term_node(source : String) -> TermNode raise {
  let green = parse_green(source)
  green_to_term_node(green, 0, Ref::new(0))
}
