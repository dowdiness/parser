///|
pub(all) enum ParseEvent {
  StartNode(SyntaxKind)
  FinishNode
  Token(SyntaxKind, String)
  Tombstone
} derive(Show, Eq)

///|
pub struct EventBuffer {
  events : Array[ParseEvent]
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
pub fn EventBuffer::mark(self : EventBuffer) -> Int {
  let index = self.events.length()
  self.events.push(Tombstone)
  index
}

///|
pub fn EventBuffer::start_at(
  self : EventBuffer,
  mark : Int,
  kind : SyntaxKind,
) -> Unit {
  self.events[mark] = StartNode(kind)
}

///|
pub fn build_tree(events : Array[ParseEvent]) -> GreenNode {
  let stack : Array[Array[GreenElement]] = [[]]
  let kinds : Array[SyntaxKind] = [SourceFile]
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
            abort(
              "build_tree: unbalanced FinishNode — no matching StartNode",
            )
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None =>
            abort("build_tree: kind stack underflow on FinishNode")
        }
        let node = GreenNode::new(kind, children)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort(
              "build_tree: parent stack empty when attaching node",
            )
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
  GreenNode::new(SourceFile, children)
}
