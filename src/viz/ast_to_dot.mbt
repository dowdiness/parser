// Generic graphviz visualizer — language-agnostic DOT renderer.
// Language-specific DotNode implementations live in their own packages.

///|
/// Trait for types that can be visualized as a Graphviz DOT graph node.
/// Implement in your language package; the generic `to_dot` renderer does the rest.
pub(open) trait DotNode {
  /// Unique integer id — used as the DOT node name (`node<id>`).
  node_id(Self) -> Int
  /// Raw label text; the renderer escapes it for DOT before writing.
  label(Self) -> String
  /// Extra DOT style attributes, e.g. `color="#c586c0", fillcolor="#c586c022"`.
  /// Return "" to use the default graph-wide node style.
  node_attrs(Self) -> String
  /// Child nodes in traversal order.
  children(Self) -> Array[Self]
  /// Label for the i-th outgoing edge, or "" for no label.
  edge_label(Self, Int) -> String
}

///|
/// Convert any DotNode tree to a Graphviz DOT string.
pub fn[T : DotNode] to_dot(node : T) -> String {
  let buf = StringBuilder::new()
  buf.write_string("digraph {\n")
  buf.write_string("  bgcolor=\"transparent\";\n")
  buf.write_string(
    "  node [shape=box, style=\"rounded,filled\", fillcolor=\"#252526\", fontname=\"Arial\", fontcolor=\"#d4d4d4\", color=\"#3c3c3c\"];\n",
  )
  buf.write_string(
    "  edge [fontname=\"Arial\", fontcolor=\"#858585\", color=\"#3c3c3c\"];\n\n",
  )
  write_node_and_edges(buf, node)
  buf.write_string("}\n")
  buf.to_string()
}

///|
fn[T : DotNode] write_node_and_edges(buf : StringBuilder, node : T) -> Unit {
  write_node_definition(buf, node)
  let cs = DotNode::children(node)
  for i = 0; i < cs.length(); i = i + 1 {
    let child = cs[i]
    buf.write_string("  node")
    buf.write_string(DotNode::node_id(node).to_string())
    buf.write_string(" -> node")
    buf.write_string(DotNode::node_id(child).to_string())
    let el = DotNode::edge_label(node, i)
    if el != "" {
      buf.write_string(" [label=\"")
      buf.write_string(el)
      buf.write_string("\"]")
    }
    buf.write_string(";\n")
    write_node_and_edges(buf, child)
  }
}

///|
fn[T : DotNode] write_node_definition(buf : StringBuilder, node : T) -> Unit {
  buf.write_string("  node")
  buf.write_string(DotNode::node_id(node).to_string())
  buf.write_string(" [label=\"")
  buf.write_string(escape_label(DotNode::label(node)))
  buf.write_string("\"]")
  let attrs = DotNode::node_attrs(node)
  if attrs != "" {
    buf.write_string(" [")
    buf.write_string(attrs)
    buf.write_string("]")
  }
  buf.write_string(";\n")
}

///|
/// Escape special characters in DOT labels.
fn escape_label(s : String) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < s.length(); i = i + 1 {
    match s.code_unit_at(i).to_char() {
      Some('"') => buf.write_string("\\\"")
      Some('\\') => buf.write_string("\\\\")
      Some('\n') => buf.write_string("\\n")
      Some(c) => buf.write_char(c)
      None => ()
    }
  }
  buf.to_string()
}
