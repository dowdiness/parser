///|
priv struct GreenParser {
  tokens : Array[TokenInfo]
  source : String
  mut position : Int
  mut last_end : Int // Track last token end to emit whitespace
  events : EventBuffer
}

///|
pub fn parse_green(source : String) -> GreenNode raise {
  let tokens = tokenize(source)
  let parser = GreenParser::new(tokens, source)
  parser.parse_source_file()
  build_tree(parser.events.events)
}

///|
fn GreenParser::new(tokens : Array[TokenInfo], source : String) -> GreenParser {
  { tokens, source, position: 0, last_end: 0, events: EventBuffer::new() }
}

///|
fn GreenParser::start_node(self : GreenParser, kind : SyntaxKind) -> Unit {
  self.events.push(StartNode(kind))
}

///|
fn GreenParser::finish_node(self : GreenParser) -> Unit {
  self.events.push(FinishNode)
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
    self.events.push(Token(WhitespaceToken, ws_text.to_string()))
  }
}

///|
fn GreenParser::emit_token(self : GreenParser, kind : SyntaxKind) -> Unit {
  let info = self.peek_info()
  self.emit_whitespace_before(info)
  let text = self.token_text(info)
  self.events.push(Token(kind, text))
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
        self.events.push(Token(WhitespaceToken, ws_text.to_string()))
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
  let mark = self.events.mark()
  self.parse_application()
  match self.peek() {
    Plus | Minus => {
      self.events.start_at(mark, BinaryExpr)
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
      self.finish_node()
    }
    _ => ()
  }
}

///|
fn GreenParser::parse_application(self : GreenParser) -> Unit raise ParseError {
  let mark = self.events.mark()
  self.parse_atom()
  match self.peek() {
    LeftParen | Identifier(_) | Integer(_) | Lambda => {
      self.events.start_at(mark, AppExpr)
      while true {
        match self.peek() {
          LeftParen | Identifier(_) | Integer(_) | Lambda => self.parse_atom()
          _ => break
        }
      }
      self.finish_node()
    }
    _ => ()
  }
}

///|
fn GreenParser::parse_atom(self : GreenParser) -> Unit raise ParseError {
  match self.peek() {
    Integer(_) => {
      self.start_node(IntLiteral)
      self.emit_token(IntToken)
      self.finish_node()
    }
    Identifier(_) => {
      self.start_node(VarRef)
      self.emit_token(IdentToken)
      self.finish_node()
    }
    Lambda => {
      self.start_node(LambdaExpr)
      self.emit_token(LambdaToken)
      match self.peek() {
        Identifier(_) => self.emit_token(IdentToken)
        token => raise ParseError("Expected parameter after λ", token)
      }
      self.expect(Dot, DotToken)
      self.parse_expression()
      self.finish_node()
    }
    If => {
      self.start_node(IfExpr)
      self.emit_token(IfKeyword)
      self.parse_expression()
      self.expect(Then, ThenKeyword)
      self.parse_expression()
      self.expect(Else, ElseKeyword)
      self.parse_expression()
      self.finish_node()
    }
    LeftParen => {
      self.start_node(ParenExpr)
      self.emit_token(LeftParenToken)
      self.parse_expression()
      self.expect(RightParen, RightParenToken)
      self.finish_node()
    }
    token => raise ParseError("Unexpected token", token)
  }
}
