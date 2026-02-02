///|
pub enum SyntaxKind {
  LambdaToken
  DotToken
  LeftParenToken
  RightParenToken
  PlusToken
  MinusToken
  IfKeyword
  ThenKeyword
  ElseKeyword
  IdentToken
  IntToken
  WhitespaceToken
  ErrorToken
  EofToken
  LambdaExpr
  AppExpr
  BinaryExpr
  IfExpr
  ParenExpr
  IntLiteral
  VarRef
  ErrorNode
  SourceFile
} derive(Show, Eq)

///|
pub fn SyntaxKind::is_token(self : SyntaxKind) -> Bool {
  match self {
    LambdaToken
    | DotToken
    | LeftParenToken
    | RightParenToken
    | PlusToken
    | MinusToken
    | IfKeyword
    | ThenKeyword
    | ElseKeyword
    | IdentToken
    | IntToken
    | WhitespaceToken
    | ErrorToken
    | EofToken => true
    _ => false
  }
}

///|
pub struct GreenToken {
  kind : SyntaxKind
  text : String
} derive(Show, Eq)

///|
pub fn GreenToken::new(kind : SyntaxKind, text : String) -> GreenToken {
  { kind, text }
}

///|
pub fn GreenToken::text_len(self : GreenToken) -> Int {
  self.text.length()
}

///|
pub enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
} derive(Show, Eq)

///|
pub fn GreenElement::text_len(self : GreenElement) -> Int {
  match self {
    Token(t) => t.text_len()
    Node(n) => n.text_len
  }
}

///|
pub fn GreenElement::kind(self : GreenElement) -> SyntaxKind {
  match self {
    Token(t) => t.kind
    Node(n) => n.kind
  }
}

///|
pub struct GreenNode {
  kind : SyntaxKind
  children : Array[GreenElement]
  text_len : Int
} derive(Show, Eq)

///|
pub fn GreenNode::new(
  kind : SyntaxKind,
  children : Array[GreenElement],
) -> GreenNode {
  let text_len = children.fold(init=0, fn(acc, elem) { acc + elem.text_len() })
  { kind, children, text_len }
}

///|
pub fn GreenNode::kind(self : GreenNode) -> SyntaxKind {
  self.kind
}

///|
/// Check if a green tree contains any error nodes or error tokens.
pub fn has_green_errors(node : GreenNode) -> Bool {
  match node.kind {
    ErrorNode => true
    _ => {
      for elem in node.children {
        match elem {
          Token(t) => if t.kind == ErrorToken { return true }
          Node(n) => if has_green_errors(n) { return true }
        }
      }
      false
    }
  }
}
