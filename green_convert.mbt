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
pub fn green_to_term_node(
  green : GreenNode,
  offset : Int,
  node_id_counter : Ref[Int],
) -> TermNode {
  fn next_id() -> Int {
    let id = node_id_counter.val
    node_id_counter.val = id + 1
    id
  }

  fn convert(g : GreenNode, off : Int) -> TermNode {
    let start = off
    let end = off + g.text_len
    match g.kind {
      IntLiteral => {
        let text = extract_token_text(g, IntToken).unwrap_or("")
        let value = @strconv.parse_int(text) catch { _ => 0 }
        TermNode::new(TermKind::Int(value), start, end, next_id(), [])
      }
      VarRef => {
        let name = extract_token_text(g, IdentToken).unwrap_or("")
        TermNode::new(TermKind::Var(name), start, end, next_id(), [])
      }
      LambdaExpr => {
        let param = extract_token_text(g, IdentToken).unwrap_or("")
        let mut child_offset = off
        for elem in g.children {
          match elem {
            Node(n) => {
              let body = convert(n, child_offset)
              return TermNode::new(
                TermKind::Lam(param),
                start,
                end,
                next_id(),
                [body],
              )
            }
            Token(t) => child_offset = child_offset + t.text_len()
          }
        }
        TermNode::new(TermKind::Lam(param), start, end, next_id(), [])
      }
      AppExpr => {
        let children : Array[TermNode] = []
        let mut child_offset = off
        for elem in g.children {
          match elem {
            Node(n) => {
              children.push(convert(n, child_offset))
              child_offset = child_offset + n.text_len
            }
            Token(t) => child_offset = child_offset + t.text_len()
          }
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
          TermNode::error("Empty AppExpr", start, next_id())
        }
      }
      BinaryExpr => {
        let ops = collect_binary_ops(g)
        let children : Array[TermNode] = []
        let mut child_offset = off
        for elem in g.children {
          match elem {
            Node(n) => {
              children.push(convert(n, child_offset))
              child_offset = child_offset + n.text_len
            }
            Token(t) => child_offset = child_offset + t.text_len()
          }
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
          TermNode::error("Empty BinaryExpr", start, next_id())
        }
      }
      IfExpr => {
        let children : Array[TermNode] = []
        let mut child_offset = off
        for elem in g.children {
          match elem {
            Node(n) => {
              children.push(convert(n, child_offset))
              child_offset = child_offset + n.text_len
            }
            Token(t) => child_offset = child_offset + t.text_len()
          }
        }
        TermNode::new(TermKind::If, start, end, next_id(), children)
      }
      ParenExpr => {
        let mut child_offset = off
        for elem in g.children {
          match elem {
            Node(n) => {
              let inner = convert(n, child_offset)
              return TermNode::new(
                inner.kind,
                start,
                end,
                next_id(),
                inner.children,
              )
            }
            Token(t) => child_offset = child_offset + t.text_len()
          }
        }
        TermNode::error("Empty ParenExpr", start, next_id())
      }
      SourceFile => {
        let child_nodes = find_child_nodes(g)
        if child_nodes.length() > 0 {
          let mut child_offset = off
          for elem in g.children {
            match elem {
              Node(n) => return convert(n, child_offset)
              Token(t) => child_offset = child_offset + t.text_len()
            }
          }
        }
        TermNode::error("Empty SourceFile", start, next_id())
      }
      _ =>
        TermNode::error(
          "Unexpected node kind: " + g.kind.to_string(),
          start,
          next_id(),
        )
    }
  }

  convert(green, offset)
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
