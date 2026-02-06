///|
/// Collect token text from all children of an ErrorNode.
fn extract_error_text(green : @syntax.GreenNode) -> String {
  let parts : Array[String] = []
  for elem in green.children {
    match elem {
      @syntax.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken && t.text != "" {
          parts.push(t.text)
        }
      @syntax.GreenElement::Node(_) => ()
    }
  }
  parts.join("")
}

///|
fn extract_token_text(green : @syntax.GreenNode, token_kind : @syntax.SyntaxKind) -> String? {
  for elem in green.children {
    match elem {
      @syntax.GreenElement::Token(t) => if t.kind == token_kind { return Some(t.text) }
      _ => continue
    }
  }
  None
}

///|
/// Compute tight start/end positions for a green node, skipping leading and
/// trailing whitespace tokens. Returns (start, end) relative to the given offset.
fn tight_span(green : @syntax.GreenNode, offset : Int) -> (Int, Int) {
  let mut pos = offset
  let mut tight_start = offset
  let mut tight_end = offset + green.text_len
  let mut found_start = false
  for elem in green.children {
    let len = elem.text_len()
    match elem {
      @syntax.GreenElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken {
          if not(found_start) {
            tight_start = pos
            found_start = true
          }
          tight_end = pos + len
        }
      @syntax.GreenElement::Node(_) => {
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
fn collect_binary_ops(green : @syntax.GreenNode) -> Array[@term.Bop] {
  let ops : Array[@term.Bop] = []
  for elem in green.children {
    match elem {
      @syntax.GreenElement::Token(t) =>
        match t.kind {
          @syntax.PlusToken => ops.push(@term.Bop::Plus)
          @syntax.MinusToken => ops.push(@term.Bop::Minus)
          _ => ()
        }
      _ => ()
    }
  }
  ops
}

///|
/// Handle multiple children from SourceFile (main expression + error nodes).
fn convert_source_file_children(
  children : Array[@term.TermNode],
  off : Int,
  counter : Ref[Int],
) -> @term.TermNode {
  fn next_id() -> Int {
    let id = counter.val
    counter.val = id + 1
    id
  }

  if children.length() == 0 {
    return @term.TermNode::error("Empty SourceFile", off, next_id())
  }
  if children.length() == 1 {
    return children[0]
  }
  // Multiple children: find the first non-error child as main, rest as error children
  let main_nodes : Array[@term.TermNode] = []
  let error_nodes : Array[@term.TermNode] = []
  for child in children {
    match child.kind {
      @term.TermKind::Error(_) => error_nodes.push(child)
      _ => main_nodes.push(child)
    }
  }
  if main_nodes.length() > 0 {
    let m = main_nodes[0]
    // Attach any extra main nodes and error nodes as children
    let extra : Array[@term.TermNode] = []
    for i = 1; i < main_nodes.length(); i = i + 1 {
      extra.push(main_nodes[i])
    }
    extra.append(error_nodes)
    if extra.length() > 0 {
      let all_children : Array[@term.TermNode] = m.children.copy()
      all_children.append(extra)
      // Extend end to cover all children so the parent span is a superset
      let mut end = m.end
      for child in extra {
        if child.end > end {
          end = child.end
        }
      }
      @term.TermNode::new(m.kind, m.start, end, next_id(), all_children)
    } else {
      m
    }
    // All children are errors — wrap them under a single error node
    // so none are discarded
  } else {
    let mut start = children[0].start
    let mut end = children[0].end
    for child in children {
      if child.start < start {
        start = child.start
      }
      if child.end > end {
        end = child.end
      }
    }
    @term.TermNode::new(
      @term.TermKind::Error("Syntax error"),
      start,
      end,
      next_id(),
      children,
    )
  }
}

///|
/// Convert a RedNode to a TermNode. Uses RedNode's offset-based position
/// computation instead of manual offset tracking.
fn convert_red(red : @syntax.RedNode, counter : Ref[Int]) -> @term.TermNode {
  fn next_id() -> Int {
    let id = counter.val
    counter.val = id + 1
    id
  }

  let g = red.green
  let off = red.start()
  match g.kind {
    @syntax.IntLiteral => {
      let text = extract_token_text(g, @syntax.IntToken).unwrap_or("")
      let value = @strconv.parse_int(text) catch { _ => 0 }
      let (tight_start, tight_end) = tight_span(g, off)
      @term.TermNode::new(@term.TermKind::Int(value), tight_start, tight_end, next_id(), [])
    }
    @syntax.VarRef => {
      let name = extract_token_text(g, @syntax.IdentToken).unwrap_or("")
      let (tight_start, tight_end) = tight_span(g, off)
      @term.TermNode::new(@term.TermKind::Var(name), tight_start, tight_end, next_id(), [])
    }
    @syntax.LambdaExpr => {
      let param = extract_token_text(g, @syntax.IdentToken).unwrap_or("")
      let (tight_start, tight_end) = tight_span(g, off)
      let red_children = red.children()
      for child in red_children {
        let body = convert_red(child, counter)
        return @term.TermNode::new(
          @term.TermKind::Lam(param),
          tight_start,
          body.end,
          next_id(),
          [body],
        )
      }
      @term.TermNode::new(@term.TermKind::Lam(param), tight_start, tight_end, next_id(), [])
    }
    @syntax.AppExpr => {
      let children : Array[@term.TermNode] = []
      let red_children = red.children()
      for child in red_children {
        children.push(convert_red(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          result = @term.TermNode::new(
            @term.TermKind::App,
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
        @term.TermNode::error("Empty AppExpr", off, next_id())
      }
    }
    @syntax.BinaryExpr => {
      let ops = collect_binary_ops(g)
      let children : Array[@term.TermNode] = []
      let red_children = red.children()
      for child in red_children {
        children.push(convert_red(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() { ops[i - 1] } else { @term.Bop::Plus }
          result = @term.TermNode::new(
            @term.TermKind::Bop(op),
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
        @term.TermNode::error("Empty BinaryExpr", off, next_id())
      }
    }
    @syntax.IfExpr => {
      let (tight_start, _) = tight_span(g, off)
      let children : Array[@term.TermNode] = []
      let red_children = red.children()
      for child in red_children {
        children.push(convert_red(child, counter))
      }
      let if_end = if children.length() > 0 {
        children[children.length() - 1].end
      } else {
        off + g.text_len
      }
      @term.TermNode::new(@term.TermKind::If, tight_start, if_end, next_id(), children)
    }
    @syntax.ParenExpr => {
      let (tight_start, tight_end) = tight_span(g, off)
      let red_children = red.children()
      for child in red_children {
        let inner = convert_red(child, counter)
        return @term.TermNode::new(
          inner.kind,
          tight_start,
          tight_end,
          next_id(),
          inner.children,
        )
      }
      @term.TermNode::error("Empty ParenExpr", off, next_id())
    }
    @syntax.ErrorNode => {
      let (tight_start, tight_end) = tight_span(g, off)
      let text = extract_error_text(g)
      let msg = if text != "" {
        "Syntax error: " + text
      } else {
        "Syntax error"
      }
      @term.TermNode::new(@term.TermKind::Error(msg), tight_start, tight_end, next_id(), [])
    }
    @syntax.SourceFile => {
      let red_children = red.children()
      let children : Array[@term.TermNode] = []
      for child in red_children {
        children.push(convert_red(child, counter))
      }
      convert_source_file_children(children, off, counter)
    }
    _ =>
      @term.TermNode::error(
        "Unexpected node kind: " + g.kind.to_string(),
        off,
        next_id(),
      )
  }
}

///|
/// Convert a RedNode (position-aware CST facade) to a TermNode.
pub fn red_to_term_node(red : @syntax.RedNode, node_id_counter : Ref[Int]) -> @term.TermNode {
  convert_red(red, node_id_counter)
}

///|
/// Convert a GreenNode to a TermNode. Preserved for backward compatibility.
/// Internally creates a RedNode and delegates to convert_red.
pub fn green_to_term_node(
  green : @syntax.GreenNode,
  offset : Int,
  node_id_counter : Ref[Int],
) -> @term.TermNode {
  let red = @syntax.RedNode::new(green, None, offset)
  convert_red(red, node_id_counter)
}

///|
pub fn green_to_term(green : @syntax.GreenNode) -> @term.Term {
  let node = green_to_term_node(green, 0, Ref::new(0))
  @term.node_to_term(node)
}

///|
pub fn parse_green_to_term_node(source : String) -> @term.TermNode raise {
  let green = parse_green(source)
  green_to_term_node(green, 0, Ref::new(0))
}
