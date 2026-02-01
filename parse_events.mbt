///|
pub enum ParseEvent {
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
        let children = stack.pop().unwrap()
        let kind = kinds.pop().unwrap()
        let node = GreenNode::new(kind, children)
        stack.last().unwrap().push(Node(node))
      }
      Token(kind, text) => {
        let token = GreenToken::new(kind, text)
        stack.last().unwrap().push(GreenElement::Token(token))
      }
      Tombstone => ()
    }
  }
  let children = stack.pop().unwrap()
  GreenNode::new(SourceFile, children)
}
