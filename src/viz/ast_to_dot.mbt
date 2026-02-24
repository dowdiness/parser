// Convert AST (AstNode) to DOT format for graphviz visualization

///|
/// Convert an AstNode to DOT format for graphviz visualization
pub fn ast_node_to_dot(node : @ast.AstNode) -> String {
  let buf = StringBuilder::new()

  // DOT header with dark theme styling
  buf.write_string("digraph {\n")
  buf.write_string("  bgcolor=\"transparent\";\n")
  buf.write_string(
    "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#252526\", fontname=\"Arial\", fontcolor=\"#d4d4d4\", color=\"#3c3c3c\"];\n",
  )
  buf.write_string(
    "  edge [fontname=\"Arial\", fontcolor=\"#858585\", color=\"#3c3c3c\"];\n\n",
  )

  // Generate nodes and edges
  write_node_and_edges(buf, node)

  // DOT footer
  buf.write_string("}\n")
  buf.to_string()
}

///|
/// Recursively write node definitions and edges
fn write_node_and_edges(buf : StringBuilder, node : @ast.AstNode) -> Unit {
  // Write this node's definition
  write_node_definition(buf, node)

  // Write edges to children and recursively process children
  for i = 0; i < node.children.length(); i = i + 1 {
    let child = node.children[i]

    // Write edge
    buf.write_string("  node")
    buf.write_string(node.node_id.to_string())
    buf.write_string(" -> node")
    buf.write_string(child.node_id.to_string())

    // Add edge label for clarity (optional, based on position)
    match node.kind {
      @ast.AstKind::Lam(_) =>
        if i == 0 {
          buf.write_string(" [label=\"body\"]")
        }
      @ast.AstKind::App =>
        if i == 0 {
          buf.write_string(" [label=\"func\"]")
        } else if i == 1 {
          buf.write_string(" [label=\"arg\"]")
        }
      @ast.AstKind::Bop(_) =>
        if i == 0 {
          buf.write_string(" [label=\"left\"]")
        } else if i == 1 {
          buf.write_string(" [label=\"right\"]")
        }
      @ast.AstKind::If =>
        if i == 0 {
          buf.write_string(" [label=\"cond\"]")
        } else if i == 1 {
          buf.write_string(" [label=\"then\"]")
        } else if i == 2 {
          buf.write_string(" [label=\"else\"]")
        }
      _ => ()
    }
    buf.write_string(";\n")

    // Recursively process child
    write_node_and_edges(buf, child)
  }
}

///|
/// Write a single node definition
fn write_node_definition(buf : StringBuilder, node : @ast.AstNode) -> Unit {
  buf.write_string("  node")
  buf.write_string(node.node_id.to_string())
  buf.write_string(" [label=\"")

  // Generate label based on kind
  match node.kind {
    @ast.AstKind::Int(n) =>
      // buf.write_string("Int\\n")
      buf.write_string(n.to_string())
    @ast.AstKind::Var(name) =>
      // buf.write_string("Var\\n")
      buf.write_string(escape_label(name))
    @ast.AstKind::Lam(param) => {
      buf.write_string("λ")
      buf.write_string(escape_label(param))
    }
    @ast.AstKind::App => buf.write_string("App")
    @ast.AstKind::Bop(@ast.Plus) => buf.write_string("+")
    @ast.AstKind::Bop(@ast.Minus) => buf.write_string("-")
    @ast.AstKind::If => buf.write_string("If")
    @ast.AstKind::Error(_msg) => buf.write_string("Error")
    // buf.write_string(escape_label(msg))
  }
  buf.write_string("\"]")

  // Add styling based on kind (color for border, fillcolor for background, fontcolor for text)
  match node.kind {
    @ast.AstKind::Error(_) =>
      buf.write_string(
        " [color=\"#ff0000\", fillcolor=\"#ff000022\", fontcolor=\"#ff6b6b\"]",
      )
    @ast.AstKind::Lam(_) =>
      buf.write_string(
        " [color=\"#c586c0\", fillcolor=\"#c586c022\", fontcolor=\"#c586c0\"]",
      )
    @ast.AstKind::Var(_) =>
      buf.write_string(
        " [color=\"#9cdcfe\", fillcolor=\"#9cdcfe22\", fontcolor=\"#9cdcfe\"]",
      )
    @ast.AstKind::Int(_) =>
      buf.write_string(
        " [color=\"#b5cea8\", fillcolor=\"#b5cea822\", fontcolor=\"#b5cea8\"]",
      )
    @ast.AstKind::Bop(_) =>
      buf.write_string(
        " [color=\"#d4d4d4\", fillcolor=\"#d4d4d422\", fontcolor=\"#d4d4d4\"]",
      )
    _ => ()
  }
  buf.write_string(";\n")
}

///|
/// Escape special characters in DOT labels
fn escape_label(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    match s.code_unit_at(i).to_char() {
      Some('"') => buf.write_string("\\\"")
      Some('\\') => buf.write_string("\\\\")
      Some('\n') => buf.write_string("\\n")
      Some(c) => buf.write_char(c)
      None => () // Skip invalid code units
    }
  }
  buf.to_string()
}
