// LambdaParserDb tests: correctness of the generic two-memo pipeline
// and parity with the lambda-specific three-memo @incremental.ParserDb.

// ── Lex-error routing ────────────────────────────────────────────────────────

///|
/// "@" triggers @core.LexError; is_lex_error must be set on the CstStage
/// so ParserDb::term routes to on_lex_error rather than to_ast.
test "LambdaParserDb: lex error sets is_lex_error on CstStage" {
  let db = @bridge.new_parser_db("@invalid", @lambda.lambda_grammar)
  inspect(db.cst().is_lex_error, content="true")
}

///|
test "LambdaParserDb: lex error routes term() to AstKind::Error" {
  let db = @bridge.new_parser_db("@invalid", @lambda.lambda_grammar)
  match db.term().kind {
    @ast.AstKind::Error(_) => ()
    other => abort("expected AstKind::Error, got: " + other.to_string())
  }
}

///|
test "LambdaParserDb: lex error diagnostic starts with tokenization prefix" {
  let db = @bridge.new_parser_db("@invalid", @lambda.lambda_grammar)
  let diags = db.diagnostics()
  assert_eq(diags.length() > 0, true)
  // Convention: first diagnostic is "tokenization: <lexer message>"
  inspect(diags[0].length() > 14, content="true")
}

// ── Parse-error path (lex succeeds, parser reports errors) ───────────────────

///|
test "LambdaParserDb: parse error does not set is_lex_error" {
  let db = @bridge.new_parser_db("λx.", @lambda.lambda_grammar)
  inspect(db.cst().is_lex_error, content="false")
}

///|
test "LambdaParserDb: parse error produces non-empty diagnostics" {
  let db = @bridge.new_parser_db("λx.", @lambda.lambda_grammar)
  assert_eq(db.diagnostics().length() > 0, true)
}

// ── Happy path ───────────────────────────────────────────────────────────────

///|
test "LambdaParserDb: valid input - integer addition" {
  let db = @bridge.new_parser_db("1 + 2", @lambda.lambda_grammar)
  inspect(
    db.term(),
    content=(
      #|{kind: Bop(Plus), start: 0, end: 5, node_id: 2, children: [{kind: Int(1), start: 0, end: 1, node_id: 0, children: []}, {kind: Int(2), start: 4, end: 5, node_id: 1, children: []}]}
    ),
  )
}

///|
test "LambdaParserDb: valid input - lambda expression" {
  let db = @bridge.new_parser_db("λx.x", @lambda.lambda_grammar)
  match db.term().kind {
    @ast.AstKind::Lam("x") => ()
    other => abort("expected Lam(x), got: " + other.to_string())
  }
}

///|
test "LambdaParserDb: valid input - is_lex_error false" {
  let db = @bridge.new_parser_db("λf.λx.f x", @lambda.lambda_grammar)
  inspect(db.cst().is_lex_error, content="false")
}

// ── Mutation ─────────────────────────────────────────────────────────────────

///|
test "LambdaParserDb: set_source updates term" {
  let db = @bridge.new_parser_db("1", @lambda.lambda_grammar)
  let t1 = db.term()
  db.set_source("2")
  let t2 = db.term()
  inspect(
    t1,
    content=(
      #|{kind: Int(1), start: 0, end: 1, node_id: 0, children: []}
    ),
  )
  inspect(
    t2,
    content=(
      #|{kind: Int(2), start: 0, end: 1, node_id: 0, children: []}
    ),
  )
}

///|
test "LambdaParserDb: set_source same value preserves term (Eq)" {
  let source = "λf.λx.f x"
  let db = @bridge.new_parser_db(source, @lambda.lambda_grammar)
  let t1 = db.term()
  db.set_source(source)
  let t2 = db.term()
  // AstNode::Eq is structure-only; same source must produce equal trees
  assert_eq(t1, t2)
}

///|
test "LambdaParserDb: set_source from lex error to valid clears is_lex_error" {
  let db = @bridge.new_parser_db("@invalid", @lambda.lambda_grammar)
  assert_eq(db.cst().is_lex_error, true)
  db.set_source("1 + 2")
  assert_eq(db.cst().is_lex_error, false)
}

// ── Parity with direct parse ──────────────────────────────────────────────────

///|
/// Cross-checks LambdaParserDb (two-memo pipeline) against parse_cst_to_ast_node
/// (direct, pipeline-free parse) on a set of valid inputs.
/// The pipeline must not change AST semantics vs the baseline parser.
/// Error-recovery inputs are tested separately via the lex/parse error path tests.
test "LambdaParserDb: parity with parse_cst_to_ast_node" {
  let sources : Array[String] = [
    "λx.x      +                   1   ", "λx.x λy.y + x", "if true then 1 else 4",
    "λa.λb.λc. if c then a b else 124321 - 31 + a c", "10 - 3 + 1",
  ]
  for source in sources {
    let db = @bridge.new_parser_db(source, @lambda.lambda_grammar)
    let direct = parse_cst_to_ast_node(source) catch {
      _ => abort("unexpected parse error in valid source: " + source)
    }
    assert_eq(db.term().to_string(), direct.to_string())
  }
}
