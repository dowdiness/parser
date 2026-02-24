///|
pub(all) enum ParseEvent {
  StartNode(RawKind)
  FinishNode
  Token(RawKind, String)
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
/// Reserve a slot and return its index. Used for retroactive StartNode placement.
/// The slot must either be claimed exactly once via start_at() or remain as
/// Tombstone (which build_tree ignores).
pub fn EventBuffer::mark(self : EventBuffer) -> Int {
  let index = self.events.length()
  self.events.push(Tombstone)
  index
}

///|
/// Retroactively fill a Tombstone slot with StartNode(kind).
/// This function enforces the mark/start_at contract:
/// - mark must be in bounds
/// - mark must still point to Tombstone
pub fn EventBuffer::start_at(
  self : EventBuffer,
  mark : Int,
  kind : RawKind,
) -> Unit {
  if mark < 0 || mark >= self.events.length() {
    abort(
      "EventBuffer::start_at: mark out of bounds, mark=" +
      mark.to_string() +
      ", len=" +
      self.events.length().to_string(),
    )
  }
  match self.events[mark] {
    Tombstone => self.events[mark] = StartNode(kind)
    _ =>
      abort(
        "EventBuffer::start_at: mark does not point to Tombstone, mark=" +
        mark.to_string(),
      )
  }
}

///|
/// Build a green tree from a flat event stream, interning all tokens through
/// the provided Interner. Structurally identical to build_tree; differs only
/// in that Token events are deduplicated via intern_token.
///
/// Use this variant when tokens will be reused across multiple parses of the
/// same document (e.g. in IncrementalParser).
///
/// `trivia_kind`: forwarded to every `CstNode::new` call; leaf tokens with
/// this kind are excluded from each node's `token_count`.
pub fn build_tree_interned(
  events : Array[ParseEvent],
  root_kind : RawKind,
  interner : Interner,
  trivia_kind? : RawKind? = None,
) -> CstNode {
  let stack : Array[Array[CstElement]] = [[]]
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
            abort(
              "build_tree_interned: unbalanced FinishNode — no matching StartNode",
            )
        }
        let kind = match kinds.pop() {
          Some(k) => k
          None =>
            abort("build_tree_interned: kind stack underflow on FinishNode")
        }
        let node = CstNode::new(kind, children, trivia_kind~)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None =>
            abort("build_tree_interned: parent stack empty when attaching node")
        }
      }
      Token(kind, text) => {
        let token = interner.intern_token(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => abort("build_tree_interned: stack empty when adding token")
        }
      }
      Tombstone => ()
    }
  }
  if stack.length() != 1 {
    abort(
      "build_tree_interned: unbalanced StartNode — missing FinishNode(s), stack=" +
      stack.length().to_string(),
    )
  }
  CstNode::new(root_kind, stack[0], trivia_kind~)
}

///|
/// Build a green tree from a flat event stream.
/// root_kind is the kind of the implicit root node (e.g., SourceFile).
///
/// `trivia_kind`: forwarded to every `CstNode::new` call; leaf tokens with
/// this kind are excluded from each node's `token_count`.
pub fn build_tree(
  events : Array[ParseEvent],
  root_kind : RawKind,
  trivia_kind? : RawKind? = None,
) -> CstNode {
  // stack and kinds move in lockstep:
  // - StartNode pushes one frame + one kind
  // - FinishNode pops one frame + one kind
  //
  // stack[0] / kinds[0] represent the implicit root passed in root_kind.
  let stack : Array[Array[CstElement]] = [[]]
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
        let node = CstNode::new(kind, children, trivia_kind~)
        match stack.last() {
          Some(parent) => parent.push(Node(node))
          None => abort("build_tree: parent stack empty when attaching node")
        }
      }
      Token(kind, text) => {
        let token = CstToken::new(kind, text)
        match stack.last() {
          Some(top) => top.push(CstElement::Token(token))
          None => abort("build_tree: stack empty when adding token")
        }
      }
      // Unclaimed marks are expected and intentionally ignored.
      Tombstone => ()
    }
  }
  // If stack is not back to the implicit root frame, we are missing one or
  // more FinishNode events.
  if stack.length() != 1 {
    abort(
      "build_tree: unbalanced StartNode — missing FinishNode(s), stack=" +
      stack.length().to_string(),
    )
  }
  CstNode::new(root_kind, stack[0], trivia_kind~)
}
