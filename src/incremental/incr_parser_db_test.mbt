///|
test "ParserDb construction returns valid cst stage" {
  let db = @incremental.ParserDb::new("x + 1")
  let stage = db.cst()
  inspect(stage.diagnostics, content="[]")
}

///|
test "ParserDb term on valid source" {
  let db = @incremental.ParserDb::new("1 + 2")
  let term = db.term()
  inspect(
    term,
    content=(
      #|{kind: Bop(Plus), start: 0, end: 5, node_id: 2, children: [{kind: Int(1), start: 0, end: 1, node_id: 0, children: []}, {kind: Int(2), start: 4, end: 5, node_id: 1, children: []}]}
    ),
  )
}

///|
test "ParserDb term on tokenization error returns error AstNode (Option B)" {
  // "@" is an unrecognized character that triggers TokenizationError in the lexer
  let db = @incremental.ParserDb::new("@invalid")
  let term = db.term()
  match term.kind {
    @ast.AstKind::Error(_) => ()
    other => abort("expected AstKind::Error, got: " + other.to_string())
  }
}

///|
test "ParserDb diagnostics on parse error" {
  let db = @incremental.ParserDb::new("\\x.") // incomplete lambda
  let diags = db.diagnostics()
  // Should have at least one diagnostic
  assert_eq(diags.length() > 0, true)
}

///|
test "ParserDb diagnostics non-empty on tokenization error" {
  // On tokenization error, cst_memo returns a placeholder CstStage
  // with diagnostics containing the tokenization error message.
  let db = @incremental.ParserDb::new("@invalid")
  let diags = db.diagnostics()
  assert_eq(diags.length() > 0, true)
}

///|
test "ParserDb set_source updates term" {
  let db = @incremental.ParserDb::new("1")
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
test "ParserDb term matches parse_cst_to_ast_node output" {
  // Validation checklist item 5: compare ParserDb::term() against direct parse
  // Uses assert_eq on string representations to avoid for-loop snapshot issues.
  let sources = ["x + 1", "\\x.x", "if 1 then 2 else 3", "1 + 2 + 3"]
  for source in sources {
    let db = @incremental.ParserDb::new(source)
    let from_db = db.term()
    let direct = @parse.parse_cst_to_ast_node(source)
    assert_eq(from_db.to_string(), direct.to_string())
  }
}
