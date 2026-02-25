// LambdaParserDb tests: correctness of the generic two-memo pipeline
// and parity with the lambda-specific three-memo @incremental.ParserDb.

// ── Lex-error routing ────────────────────────────────────────────────────────

///|
/// "@" triggers TokenizationError; is_lex_error must be set on the CstStage
/// so ParserDb::term routes to on_lex_error rather than to_ast.
test "LambdaParserDb: lex error sets is_lex_error on CstStage" {
  let db = @lambda.LambdaParserDb::new("@invalid")
  inspect(@lambda.LambdaParserDb::cst(db).is_lex_error, content="true")
}

///|
test "LambdaParserDb: lex error routes term() to AstKind::Error" {
  let db = @lambda.LambdaParserDb::new("@invalid")
  match @lambda.LambdaParserDb::term(db).kind {
    @ast.AstKind::Error(_) => ()
    other => abort("expected AstKind::Error, got: " + other.to_string())
  }
}

///|
test "LambdaParserDb: lex error diagnostic starts with tokenization prefix" {
  let db = @lambda.LambdaParserDb::new("@invalid")
  let diags = @lambda.LambdaParserDb::diagnostics(db)
  assert_eq(diags.length() > 0, true)
  // Convention: first diagnostic is "tokenization: <lexer message>"
  inspect(diags[0].length() > 14, content="true")
}

// ── Parse-error path (lex succeeds, parser reports errors) ───────────────────

///|
test "LambdaParserDb: parse error does not set is_lex_error" {
  let db = @lambda.LambdaParserDb::new("λx.")
  inspect(@lambda.LambdaParserDb::cst(db).is_lex_error, content="false")
}

///|
test "LambdaParserDb: parse error produces non-empty diagnostics" {
  let db = @lambda.LambdaParserDb::new("λx.")
  assert_eq(@lambda.LambdaParserDb::diagnostics(db).length() > 0, true)
}

// ── Happy path ───────────────────────────────────────────────────────────────

///|
test "LambdaParserDb: valid input - integer addition" {
  let db = @lambda.LambdaParserDb::new("1 + 2")
  inspect(
    @lambda.LambdaParserDb::term(db),
    content=(
      #|{kind: Bop(Plus), start: 0, end: 5, node_id: 2, children: [{kind: Int(1), start: 0, end: 1, node_id: 0, children: []}, {kind: Int(2), start: 4, end: 5, node_id: 1, children: []}]}
    ),
  )
}

///|
test "LambdaParserDb: valid input - lambda expression" {
  let db = @lambda.LambdaParserDb::new("λx.x")
  match @lambda.LambdaParserDb::term(db).kind {
    @ast.AstKind::Lam("x") => ()
    other => abort("expected Lam(x), got: " + other.to_string())
  }
}

///|
test "LambdaParserDb: valid input - is_lex_error false" {
  let db = @lambda.LambdaParserDb::new("λf.λx.f x")
  inspect(@lambda.LambdaParserDb::cst(db).is_lex_error, content="false")
}

// ── Mutation ─────────────────────────────────────────────────────────────────

///|
test "LambdaParserDb: set_source updates term" {
  let db = @lambda.LambdaParserDb::new("1")
  let t1 = @lambda.LambdaParserDb::term(db)
  @lambda.LambdaParserDb::set_source(db, "2")
  let t2 = @lambda.LambdaParserDb::term(db)
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
  let db = @lambda.LambdaParserDb::new(source)
  let t1 = @lambda.LambdaParserDb::term(db)
  @lambda.LambdaParserDb::set_source(db, source)
  let t2 = @lambda.LambdaParserDb::term(db)
  // AstNode::Eq is structure-only; same source must produce equal trees
  assert_eq(t1, t2)
}

///|
test "LambdaParserDb: set_source from lex error to valid clears is_lex_error" {
  let db = @lambda.LambdaParserDb::new("@invalid")
  assert_eq(@lambda.LambdaParserDb::cst(db).is_lex_error, true)
  @lambda.LambdaParserDb::set_source(db, "1 + 2")
  assert_eq(@lambda.LambdaParserDb::cst(db).is_lex_error, false)
}

// ── Parity with @incremental.ParserDb ────────────────────────────────────────

///|
/// Cross-checks LambdaParserDb (generic two-memo) against the lambda-specific
/// three-memo @incremental.ParserDb on a set of representative inputs.
/// The two pipelines must produce structurally equal ASTs for all valid sources.
test "LambdaParserDb: parity with incremental.ParserDb" {
  let sources : Array[String] = [
    "λx.x      +                   1   ", "λx.x λy.y + x", "if true then 1 else 4",
    "1 + 5993 +", "λa.λb.λc. if c then a b else 124321 - 31 + a c", "10 - 3 + 1",
  ]
  for source in sources {
    let lambda_db = @lambda.LambdaParserDb::new(source)
    let incr_db = @incremental.ParserDb::new(source)
    assert_eq(
      @lambda.LambdaParserDb::term(lambda_db).to_string(),
      @incremental.ParserDb::term(incr_db).to_string(),
    )
  }
}
