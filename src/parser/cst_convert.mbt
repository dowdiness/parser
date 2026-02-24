///|
/// Collect token text from all children of an ErrorNode.
fn extract_error_text(cst : @seam.CstNode) -> String {
  let parts : Array[String] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() && t.text != "" {
          parts.push(t.text)
        }
      @seam.CstElement::Node(_) => ()
    }
  }
  parts.join("")
}

///|
fn extract_token_text(
  cst : @seam.CstNode,
  token_kind : @seam.RawKind,
) -> String? {
  for elem in cst.children {
    match elem {
      @seam.CstElement::Token(t) =>
        if t.kind == token_kind {
          return Some(t.text)
        }
      _ => continue
    }
  }
  None
}

///|
/// Compute tight start/end positions for a cst node, skipping leading and
/// trailing whitespace tokens. Returns (start, end) relative to the given offset.
fn tight_span(cst : @seam.CstNode, offset : Int) -> (Int, Int) {
  let mut pos = offset
  let mut tight_start = offset
  let mut tight_end = offset + cst.text_len
  let mut found_start = false
  for elem in cst.children {
    let len = elem.text_len()
    match elem {
      @seam.CstElement::Token(t) =>
        if t.kind != @syntax.WhitespaceToken.to_raw() {
          if not(found_start) {
            tight_start = pos
            found_start = true
          }
          tight_end = pos + len
        }
      @seam.CstElement::Node(_) => {
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
fn collect_binary_ops(cst : @seam.CstNode) -> Array[@ast.Bop] {
  let ops : Array[@ast.Bop] = []
  for elem in cst.children {
    match elem {
      @seam.CstElement::Token(t) =>
        if t.kind == @syntax.PlusToken.to_raw() {
          ops.push(@ast.Bop::Plus)
        } else if t.kind == @syntax.MinusToken.to_raw() {
          ops.push(@ast.Bop::Minus)
        }
      _ => ()
    }
  }
  ops
}

///|
/// Handle multiple children from SourceFile (main expression + error nodes).
fn convert_source_file_children(
  children : Array[@ast.AstNode],
  off : Int,
  counter : Ref[Int],
) -> @ast.AstNode {
  fn next_id() -> Int {
    let id = counter.val
    counter.val = id + 1
    id
  }

  if children.length() == 0 {
    return @ast.AstNode::error("Empty SourceFile", off, next_id())
  }
  if children.length() == 1 {
    return children[0]
  }
  // Multiple children: find the first non-error child as main, rest as error children
  let main_nodes : Array[@ast.AstNode] = []
  let error_nodes : Array[@ast.AstNode] = []
  for child in children {
    match child.kind {
      @ast.AstKind::Error(_) => error_nodes.push(child)
      _ => main_nodes.push(child)
    }
  }
  if main_nodes.length() > 0 {
    let m = main_nodes[0]
    // Attach any extra main nodes and error nodes as children
    let extra : Array[@ast.AstNode] = []
    for i = 1; i < main_nodes.length(); i = i + 1 {
      extra.push(main_nodes[i])
    }
    extra.append(error_nodes)
    if extra.length() > 0 {
      let all_children : Array[@ast.AstNode] = m.children.copy()
      all_children.append(extra)
      // Extend end to cover all children so the parent span is a superset
      let mut end = m.end
      for child in extra {
        if child.end > end {
          end = child.end
        }
      }
      @ast.AstNode::new(m.kind, m.start, end, next_id(), all_children)
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
    @ast.AstNode::new(
      @ast.AstKind::Error("Syntax error"),
      start,
      end,
      next_id(),
      children,
    )
  }
}

///|
/// Convert a SyntaxNode to an AstNode. Uses SyntaxNode's offset-based position
/// computation instead of manual offset tracking.
fn convert_syntax_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @ast.AstNode {
  fn next_id() -> Int {
    let id = counter.val
    counter.val = id + 1
    id
  }

  let g = node.green
  let off = node.start()
  match @syntax.SyntaxKind::from_raw(g.kind) {
    @syntax.IntLiteral => {
      let text = extract_token_text(g, @syntax.IntToken.to_raw()).unwrap_or("")
      let value = @strconv.parse_int(text) catch { _ => 0 }
      let (tight_start, tight_end) = tight_span(g, off)
      @ast.AstNode::new(
        @ast.AstKind::Int(value),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.VarRef => {
      let name = extract_token_text(g, @syntax.IdentToken.to_raw()).unwrap_or(
        "",
      )
      let (tight_start, tight_end) = tight_span(g, off)
      @ast.AstNode::new(
        @ast.AstKind::Var(name),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.LambdaExpr => {
      let param = extract_token_text(g, @syntax.IdentToken.to_raw()).unwrap_or(
        "",
      )
      let (tight_start, tight_end) = tight_span(g, off)
      let red_children = node.children()
      for child in red_children {
        let body = convert_syntax_node(child, counter)
        return @ast.AstNode::new(
          @ast.AstKind::Lam(param),
          tight_start,
          body.end,
          next_id(),
          [body],
        )
      }
      @ast.AstNode::new(
        @ast.AstKind::Lam(param),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.AppExpr => {
      let children : Array[@ast.AstNode] = []
      let red_children = node.children()
      for child in red_children {
        children.push(convert_syntax_node(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          result = @ast.AstNode::new(
            @ast.AstKind::App,
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
        @ast.AstNode::error("Empty AppExpr", off, next_id())
      }
    }
    @syntax.BinaryExpr => {
      let ops = collect_binary_ops(g)
      let children : Array[@ast.AstNode] = []
      let red_children = node.children()
      for child in red_children {
        children.push(convert_syntax_node(child, counter))
      }
      if children.length() >= 2 {
        let mut result = children[0]
        for i = 1; i < children.length(); i = i + 1 {
          let op = if i - 1 < ops.length() {
            ops[i - 1]
          } else {
            @ast.Bop::Plus
          }
          result = @ast.AstNode::new(
            @ast.AstKind::Bop(op),
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
        @ast.AstNode::error("Empty BinaryExpr", off, next_id())
      }
    }
    @syntax.IfExpr => {
      let (tight_start, _) = tight_span(g, off)
      let children : Array[@ast.AstNode] = []
      let red_children = node.children()
      for child in red_children {
        children.push(convert_syntax_node(child, counter))
      }
      let if_end = if children.length() > 0 {
        children[children.length() - 1].end
      } else {
        off + g.text_len
      }
      @ast.AstNode::new(
        @ast.AstKind::If,
        tight_start,
        if_end,
        next_id(),
        children,
      )
    }
    @syntax.ParenExpr => {
      let (tight_start, tight_end) = tight_span(g, off)
      let red_children = node.children()
      for child in red_children {
        let inner = convert_syntax_node(child, counter)
        return @ast.AstNode::new(
          inner.kind,
          tight_start,
          tight_end,
          next_id(),
          inner.children,
        )
      }
      @ast.AstNode::error("Empty ParenExpr", off, next_id())
    }
    @syntax.ErrorNode => {
      let (tight_start, tight_end) = tight_span(g, off)
      let text = extract_error_text(g)
      let msg = if text != "" {
        "Syntax error: " + text
      } else {
        "Syntax error"
      }
      @ast.AstNode::new(
        @ast.AstKind::Error(msg),
        tight_start,
        tight_end,
        next_id(),
        [],
      )
    }
    @syntax.SourceFile => {
      let red_children = node.children()
      let children : Array[@ast.AstNode] = []
      for child in red_children {
        children.push(convert_syntax_node(child, counter))
      }
      convert_source_file_children(children, off, counter)
    }
    _ =>
      @ast.AstNode::error(
        "Unexpected node kind: " + g.kind.to_string(),
        off,
        next_id(),
      )
  }
}

///|
/// Convert a SyntaxNode (position-aware CST facade) to an AstNode.
pub fn syntax_node_to_ast_node(
  node : @seam.SyntaxNode,
  node_id_counter : Ref[Int],
) -> @ast.AstNode {
  convert_syntax_node(node, node_id_counter)
}

///|
/// Convert a CstNode to an AstNode. Preserved for backward compatibility.
/// Internally creates a SyntaxNode and delegates to convert_syntax_node.
pub fn cst_to_ast_node(
  cst : @seam.CstNode,
  offset : Int,
  node_id_counter : Ref[Int],
) -> @ast.AstNode {
  let red = @seam.SyntaxNode::new(cst, None, offset)
  convert_syntax_node(red, node_id_counter)
}

///|
pub fn cst_to_ast(cst : @seam.CstNode) -> @ast.Ast {
  let node = cst_to_ast_node(cst, 0, Ref::new(0))
  @ast.node_to_ast(node)
}

///|
pub fn parse_cst_to_ast_node(source : String) -> @ast.AstNode raise {
  let cst = parse_cst(source)
  cst_to_ast_node(cst, 0, Ref::new(0))
}
