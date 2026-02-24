// Parser for Lambda Calculus expressions

///|
pub suberror ParseError {
  ParseError(String, @token.Token)
}

///|
/// Parse the input string into a Term (without position information)
///
/// This is a wrapper around parse_tree that discards position information.
pub fn parse(input : String) -> @ast.Term raise {
  let node = parse_tree(input)
  @ast.node_to_term(node)
}

///|
/// Parser state with node ID counter
priv struct Parser {
  tokens : Array[@token.TokenInfo]
  mut position : Int
  mut node_id_counter : Int
}

///|
fn make_parser(tokens : Array[@token.TokenInfo]) -> Parser {
  { tokens, position: 0, node_id_counter: 0 }
}

///|
fn next_node_id(parser : Parser) -> Int {
  let id = parser.node_id_counter
  parser.node_id_counter = parser.node_id_counter + 1
  id
}

///|
fn peek(parser : Parser) -> @token.Token {
  if parser.position < parser.tokens.length() {
    parser.tokens[parser.position].token
  } else {
    @token.EOF
  }
}

///|
fn peek_info(parser : Parser) -> @token.TokenInfo {
  if parser.position < parser.tokens.length() {
    parser.tokens[parser.position]
  } else {
    @token.TokenInfo::new(@token.EOF, 0, 0)
  }
}

///|
fn advance(parser : Parser) -> Parser {
  parser.position = parser.position + 1
  parser
}

///|
fn expect(parser : Parser, expected : @token.Token) -> Parser raise ParseError {
  let current = peek(parser)
  match (current, expected) {
    (a, b) if a == b => advance(parser)
    _ => raise ParseError("Expected token", expected)
  }
}

///|
/// Parse the input string into an AstNode with position tracking
///
/// Routes through the green tree (CST) as the canonical intermediate
/// representation: parse_cst → cst_to_ast_node.
pub fn parse_tree(input : String) -> @ast.AstNode raise {
  let green = parse_cst(input)
  cst_to_ast_node(green, 0, Ref::new(0))
}

///|
/// Parse a pre-tokenized input into an AstNode with position tracking
pub fn parse_tree_from_tokens(
  tokens : Array[@token.TokenInfo],
) -> @ast.AstNode raise {
  let parser = make_parser(tokens)
  letrec parse_expression = fn(
    parser : Parser,
  ) -> (Parser, @ast.AstNode) raise {
    parse_binary_op(parser)
  }
  and parse_binary_op = fn(parser : Parser) -> (Parser, @ast.AstNode) raise {
    let (parser, left) = parse_application(parser)
    loop (parser, left) {
      (parser, term) =>
        match peek(parser) {
          @token.Plus => {
            let parser = advance(parser)
            let (parser, right) = parse_application(parser)
            let start = term.start
            let end = right.end
            let node_id = next_node_id(parser)
            let node = @ast.AstNode::new(
              @ast.AstKind::Bop(@ast.Bop::Plus),
              start,
              end,
              node_id,
              [term, right],
            )
            continue (parser, node)
          }
          @token.Minus => {
            let parser = advance(parser)
            let (parser, right) = parse_application(parser)
            let start = term.start
            let end = right.end
            let node_id = next_node_id(parser)
            let node = @ast.AstNode::new(
              @ast.AstKind::Bop(@ast.Bop::Minus),
              start,
              end,
              node_id,
              [term, right],
            )
            continue (parser, node)
          }
          _ => break (parser, term)
        }
    }
  }
  and parse_application = fn(parser : Parser) -> (Parser, @ast.AstNode) raise {
    let (parser, first) = parse_atom(parser)
    loop (parser, first) {
      (parser, acc) =>
        match peek(parser) {
          @token.LeftParen
          | @token.Identifier(_)
          | @token.Integer(_)
          | @token.Lambda => {
            let (parser, next) = parse_atom(parser)
            let start = acc.start
            let end = next.end
            let node_id = next_node_id(parser)
            let node = @ast.AstNode::new(
              @ast.AstKind::App,
              start,
              end,
              node_id,
              [acc, next],
            )
            continue (parser, node)
          }
          _ => break (parser, acc)
        }
    }
  }
  and parse_atom = fn(parser : Parser) -> (Parser, @ast.AstNode) raise {
    let token_info = peek_info(parser)
    match token_info.token {
      @token.Integer(n) => {
        let node_id = next_node_id(parser)
        let node = @ast.AstNode::new(
          @ast.AstKind::Int(n),
          token_info.start,
          token_info.end,
          node_id,
          [],
        )
        (advance(parser), node)
      }
      @token.Identifier(name) => {
        let node_id = next_node_id(parser)
        let node = @ast.AstNode::new(
          @ast.AstKind::Var(name),
          token_info.start,
          token_info.end,
          node_id,
          [],
        )
        (advance(parser), node)
      }
      @token.Lambda => {
        let lambda_start = token_info.start
        let parser = advance(parser)
        let param_info = peek_info(parser)
        match param_info.token {
          @token.Identifier(param) => {
            let parser = advance(parser)
            let parser = expect(parser, @token.Dot)
            let (parser, body) = parse_expression(parser)
            let node_id = next_node_id(parser)
            let node = @ast.AstNode::new(
              @ast.AstKind::Lam(param),
              lambda_start,
              body.end,
              node_id,
              [body],
            )
            (parser, node)
          }
          token => raise ParseError("Expected parameter after λ", token)
        }
      }
      @token.If => {
        let if_start = token_info.start
        let parser = advance(parser)
        let (parser, condition) = parse_expression(parser)
        let parser = expect(parser, @token.Then)
        let (parser, then_expr) = parse_expression(parser)
        let parser = expect(parser, @token.Else)
        let (parser, else_expr) = parse_expression(parser)
        let node_id = next_node_id(parser)
        let node = @ast.AstNode::new(
          @ast.AstKind::If,
          if_start,
          else_expr.end,
          node_id,
          [condition, then_expr, else_expr],
        )
        (parser, node)
      }
      @token.LeftParen => {
        let paren_start = token_info.start
        let parser = advance(parser)
        let (parser, expr) = parse_expression(parser)
        let close_info = peek_info(parser)
        let parser = expect(parser, @token.RightParen)
        // Update the end position to include the closing paren
        let node_id = next_node_id(parser)
        let node = @ast.AstNode::new(
          expr.kind,
          paren_start,
          close_info.end,
          node_id,
          expr.children,
        )
        (parser, node)
      }
      token => raise ParseError("Unexpected token", token)
    }
  }

  let (final_parser, expr) = parse_expression(parser)
  match peek(final_parser) {
    @token.EOF => expr
    token => raise ParseError("Unexpected tokens after expression", token)
  }
}
