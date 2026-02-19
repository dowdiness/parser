///|
pub(all) enum SyntaxKind {
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
pub fn SyntaxKind::to_raw(self : SyntaxKind) -> @green_tree.RawKind {
  let n : Int = match self {
    LambdaToken => 0
    DotToken => 1
    LeftParenToken => 2
    RightParenToken => 3
    PlusToken => 4
    MinusToken => 5
    IfKeyword => 6
    ThenKeyword => 7
    ElseKeyword => 8
    IdentToken => 9
    IntToken => 10
    WhitespaceToken => 11
    ErrorToken => 12
    EofToken => 13
    LambdaExpr => 14
    AppExpr => 15
    BinaryExpr => 16
    IfExpr => 17
    ParenExpr => 18
    IntLiteral => 19
    VarRef => 20
    ErrorNode => 21
    SourceFile => 22
  }
  @green_tree.RawKind(n)
}

///|
pub fn SyntaxKind::from_raw(raw : @green_tree.RawKind) -> SyntaxKind {
  let @green_tree.RawKind(n) = raw
  match n {
    0 => LambdaToken
    1 => DotToken
    2 => LeftParenToken
    3 => RightParenToken
    4 => PlusToken
    5 => MinusToken
    6 => IfKeyword
    7 => ThenKeyword
    8 => ElseKeyword
    9 => IdentToken
    10 => IntToken
    11 => WhitespaceToken
    12 => ErrorToken
    13 => EofToken
    14 => LambdaExpr
    15 => AppExpr
    16 => BinaryExpr
    17 => IfExpr
    18 => ParenExpr
    19 => IntLiteral
    20 => VarRef
    21 => ErrorNode
    22 => SourceFile
    _ => ErrorNode
  }
}
