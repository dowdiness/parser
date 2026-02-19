///|
pub(all) enum ParseEvent {
  StartNode(RawKind)
  FinishNode
  Token(RawKind, String)
  Tombstone
} derive(Show, Eq)

///|
pub struct EventBuffer {
  pub events : Array[ParseEvent]
}

///|
pub fn EventBuffer::new() -> EventBuffer {
  { events: [] }
}

///|
pub fn EventBuffer::push(self : EventBuffer, event : ParseEvent) -> Unit {
  self.events.push(event)
}

///|
/// Reserve a slot and return its index. Used for retroactive StartNode placement.
pub fn EventBuffer::mark(self : EventBuffer) -> Int {
  let index = self.events.length()
  self.events.push(Tombstone)
  index
}

///|
/// Retroactively fill a Tombstone slot with StartNode(kind).
pub fn EventBuffer::start_at(
  self : EventBuffer,
  mark : Int,
  kind : RawKind,
) -> Unit {
  self.events[mark] = StartNode(kind)
}

///|
/// Build a green tree from a flat event stream.
/// root_kind is the kind of the implicit root node (e.g., SourceFile).
pub fn build_tree(events : Array[ParseEvent], root_kind : RawKind) -> GreenNode {
  let stack : Array[Array[GreenElement]] = [[]]
  let kinds : Array[RawKind] = [root_kind]
  for event in events {
    match event {
      StartNode(kind) => {
        stack.push([])
        kinds.push(kind)
      }
      FinishNode => {
        let children = match stack.pop() {
          Some(c) => c
          None =>
            abort("build_tree: unbalanced FinishNode — no matching StartNode")
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None => abort("build_tree: kind stack underflow on FinishNode")
        }
        let node = GreenNode::new(kind, children)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => abort("build_tree: parent stack empty when attaching node")
        }
      }
      Token(kind, text) => {
        let token = GreenToken::new(kind, text)
        match stack.last() {
          Some(top) => top.push(GreenElement::Token(token))
          None => abort("build_tree: stack empty when adding token")
        }
      }
      Tombstone => ()
    }
  }
  let children = match stack.pop() {
    Some(c) => c
    None => abort("build_tree: stack empty at end — mismatched events")
  }
  GreenNode::new(root_kind, children)
}
