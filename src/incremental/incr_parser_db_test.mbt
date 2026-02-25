///|
test "ParserDb construction returns valid cst stage" {
  let db = @incremental.ParserDb::new("x + 1")
  let stage = db.cst()
  inspect(stage.diagnostics, content="[]")
}
