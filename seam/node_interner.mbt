///|
/// Session-scoped node intern table.
///
/// Deduplicates CstNode objects by structural identity: every call to
/// intern_node with a structurally equal CstNode returns the first-seen
/// reference. Lookup uses CstNode::Hash (the cached structural hash, O(1))
/// as a fast path, then CstNode::Eq for collision resolution.
///
/// **trivia_kind invariant:** All `CstNode::new` calls feeding this interner
/// MUST use the same `trivia_kind` value. `CstNode::Eq` compares `kind` and
/// `children` but NOT `token_count`, which depends on `trivia_kind`. Mixing
/// trivia policies within one interner silently canonicalizes to the first-seen
/// `token_count`, producing incorrect values for subsequent callers.
///
/// Lifetime: own one NodeInterner per parse session (e.g. per IncrementalParser).
/// Not thread-safe.
pub struct NodeInterner {
  priv nodes : @hashmap.HashMap[CstNode, CstNode]
}

///|
/// Create a new empty NodeInterner.
pub fn NodeInterner::new() -> NodeInterner {
  { nodes: @hashmap.HashMap::new() }
}

///|
/// Return the canonical CstNode structurally equal to `node`.
/// First call for a given structure: stores and returns `node`.
/// Subsequent calls with an equal structure: returns the first-seen reference.
pub fn NodeInterner::intern_node(
  self : NodeInterner,
  node : CstNode,
) -> CstNode {
  if self.nodes.get(node) is Some(n) {
    n
  } else {
    self.nodes.set(node, node)
    node
  }
}

///|
/// Number of distinct CstNode structures currently interned.
pub fn NodeInterner::size(self : NodeInterner) -> Int {
  self.nodes.length()
}

///|
/// Clear all interned nodes. The NodeInterner can be reused after this call.
pub fn NodeInterner::clear(self : NodeInterner) -> Unit {
  self.nodes.clear()
}
