///|
priv struct GreenParser {
  tokens : Array[TokenInfo]
  source : String
  mut position : Int
  mut last_end : Int // Track last token end to emit whitespace
  builder : TreeBuilder
}

///|
pub fn parse_green(source : String) -> GreenNode raise {
  let tokens = tokenize(source)
  let parser = GreenParser::new(tokens, source)
  parser.parse_source_file()
  parser.builder.finish()
}

///|
fn GreenParser::new(tokens : Array[TokenInfo], source : String) -> GreenParser {
  { tokens, source, position: 0, last_end: 0, builder: TreeBuilder::new() }
}

///|
fn GreenParser::peek(self : GreenParser) -> Token {
  if self.position < self.tokens.length() {
    self.tokens[self.position].token
  } else {
    EOF
  }
}

///|
fn GreenParser::peek_info(self : GreenParser) -> TokenInfo {
  if self.position < self.tokens.length() {
    self.tokens[self.position]
  } else {
    TokenInfo::new(EOF, 0, 0)
  }
}

///|
fn GreenParser::advance(self : GreenParser) -> Unit {
  self.position = self.position + 1
}

///|
fn GreenParser::token_text(self : GreenParser, info : TokenInfo) -> String {
  let slice : StringView = self.source[info.start:info.end] catch { _ => "" }
  slice.to_string()
}

///|
fn GreenParser::emit_whitespace_before(
  self : GreenParser,
  info : TokenInfo,
) -> Unit {
  if info.start > self.last_end {
    let ws_text : StringView = self.source[self.last_end:info.start] catch {
        _ => ""
      }
    self.builder.token(WhitespaceToken, ws_text.to_string())
  }
}

///|
fn GreenParser::emit_token(self : GreenParser, kind : SyntaxKind) -> Unit {
  let info = self.peek_info()
  self.emit_whitespace_before(info)
  let text = self.token_text(info)
  self.builder.token(kind, text)
  self.last_end = info.end
  self.advance()
}

///|
fn GreenParser::expect(
  self : GreenParser,
  expected : Token,
  kind : SyntaxKind,
) -> Unit raise ParseError {
  let current = self.peek()
  match (current, expected) {
    (a, b) if a == b => self.emit_token(kind)
    _ => raise ParseError("Expected token", expected)
  }
}

///|
fn GreenParser::parse_source_file(self : GreenParser) -> Unit raise ParseError {
  self.parse_expression()
  match self.peek() {
    EOF =>
      if self.last_end < self.source.length() {
        let ws_text : StringView = self.source[self.last_end:self.source.length()] catch {
            _ => ""
          }
        self.builder.token(WhitespaceToken, ws_text.to_string())
        self.last_end = self.source.length()
      }
    token => raise ParseError("Unexpected tokens after expression", token)
  }
}

///|
fn GreenParser::parse_expression(self : GreenParser) -> Unit raise ParseError {
  self.parse_binary_op()
}

///|
fn GreenParser::parse_binary_op(self : GreenParser) -> Unit raise ParseError {
  self.parse_application()
  match self.peek() {
    Plus | Minus => {
      // We have a binary op - need to wrap in BinaryExpr
      // The left operand was already parsed, so we use a marker approach
      let left_children = self.builder.0.last().unwrap().pop()
      self.builder.start_node(BinaryExpr)
      match left_children {
        Some(child) => self.builder.0.last().unwrap().push(child)
        None => ()
      }
      while true {
        match self.peek() {
          Plus => {
            self.emit_token(PlusToken)
            self.parse_application()
          }
          Minus => {
            self.emit_token(MinusToken)
            self.parse_application()
          }
          _ => break
        }
      }
      self.builder.finish_node(BinaryExpr)
    }
    _ => ()
  }
}

///|
fn GreenParser::parse_application(self : GreenParser) -> Unit raise ParseError {
  self.parse_atom()
  match self.peek() {
    LeftParen | Identifier(_) | Integer(_) | Lambda => {
      // We have application - wrap left operand
      let left_child = self.builder.0.last().unwrap().pop()
      self.builder.start_node(AppExpr)
      match left_child {
        Some(child) => self.builder.0.last().unwrap().push(child)
        None => ()
      }
      while true {
        match self.peek() {
          LeftParen | Identifier(_) | Integer(_) | Lambda => self.parse_atom()
          _ => break
        }
      }
      self.builder.finish_node(AppExpr)
    }
    _ => ()
  }
}

///|
fn GreenParser::parse_atom(self : GreenParser) -> Unit raise ParseError {
  match self.peek() {
    Integer(_) => {
      self.builder.start_node(IntLiteral)
      self.emit_token(IntToken)
      self.builder.finish_node(IntLiteral)
    }
    Identifier(_) => {
      self.builder.start_node(VarRef)
      self.emit_token(IdentToken)
      self.builder.finish_node(VarRef)
    }
    Lambda => {
      self.builder.start_node(LambdaExpr)
      self.emit_token(LambdaToken)
      match self.peek() {
        Identifier(_) => self.emit_token(IdentToken)
        token => raise ParseError("Expected parameter after λ", token)
      }
      self.expect(Dot, DotToken)
      self.parse_expression()
      self.builder.finish_node(LambdaExpr)
    }
    If => {
      self.builder.start_node(IfExpr)
      self.emit_token(IfKeyword)
      self.parse_expression()
      self.expect(Then, ThenKeyword)
      self.parse_expression()
      self.expect(Else, ElseKeyword)
      self.parse_expression()
      self.builder.finish_node(IfExpr)
    }
    LeftParen => {
      self.builder.start_node(ParenExpr)
      self.emit_token(LeftParenToken)
      self.parse_expression()
      self.expect(RightParen, RightParenToken)
      self.builder.finish_node(ParenExpr)
    }
    token => raise ParseError("Unexpected token", token)
  }
}
