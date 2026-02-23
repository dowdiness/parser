// Integration test: minimal two-token language (integers and '+')
// Kept in _wbtest.mbt so test types don't appear in pkg.generated.mbti.

///|
// Test language: integers and '+' only (with whitespace)
enum TestTok {
  Num(Int)
  Plus
  Ws
  TokEof
} derive(Eq, Show)

///|
enum TestKind {
  KNum
  KPlus
  KExpr
  KRoot
  KWs
  KErr
} derive(Show)

///|
fn test_kind_raw(k : TestKind) -> @green_tree.RawKind {
  let n = match k {
    KNum => 0
    KPlus => 1
    KExpr => 2
    KRoot => 3
    KWs => 4
    KErr => 5
  }
  @green_tree.RawKind(n)
}

///|
fn test_tokenize(src : String) -> Array[TokenInfo[TestTok]] {
  let result : Array[TokenInfo[TestTok]] = []
  let mut i = 0
  while i < src.length() {
    let code = src.code_unit_at(i).to_int()
    if code == 32 {
      // space
      let start = i
      while i < src.length() && src.code_unit_at(i).to_int() == 32 {
        i = i + 1
      }
      result.push({ token: TestTok::Ws, start, end: i })
    } else if code >= 48 && code <= 57 {
      // digit
      let start = i
      let mut n = code - 48
      i = i + 1
      while i < src.length() {
        let d = src.code_unit_at(i).to_int()
        if d >= 48 && d <= 57 {
          n = n * 10 + d - 48
          i = i + 1
        } else {
          break
        }
      }
      result.push({ token: TestTok::Num(n), start, end: i })
    } else if code == 43 {
      // '+'
      result.push({ token: TestTok::Plus, start: i, end: i + 1 })
      i = i + 1
    } else {
      i = i + 1
    }
  }
  result
}

///|
let test_spec : LanguageSpec[TestTok, TestKind] = {
  kind_to_raw: test_kind_raw,
  token_is_eof: fn(t) { t == TestTok::TokEof },
  token_is_trivia: fn(t) { t == TestTok::Ws },
  tokens_equal: fn(a, b) { a == b },
  whitespace_kind: KWs,
  error_kind: KErr,
  root_kind: KRoot,
  eof_token: TestTok::TokEof,
}

///|
fn test_grammar(ctx : ParserContext[TestTok, TestKind]) -> Unit {
  let mark = ctx.mark()
  match ctx.peek() {
    TestTok::Num(_) => ctx.emit_token(KNum)
    _ => {
      ctx.error("expected number")
      return
    }
  }
  if ctx.at(TestTok::Plus) {
    ctx.start_at(mark, KExpr)
    while ctx.at(TestTok::Plus) {
      ctx.emit_token(KPlus)
      match ctx.peek() {
        TestTok::Num(_) => ctx.emit_token(KNum)
        _ => ctx.error("expected number after +")
      }
    }
    ctx.finish_node()
  }
}

///|
test "parse_with: simple number" {
  let (tree, errors) = parse_with("42", test_spec, test_tokenize, test_grammar)
  inspect(errors.length(), content="0")
  inspect(tree.text_len, content="2")
}

///|
test "parse_with: addition expression" {
  let (tree, errors) = parse_with(
    "1 + 2 + 3", test_spec, test_tokenize, test_grammar,
  )
  inspect(errors.length(), content="0")
  inspect(tree.text_len, content="9")
}

///|
test "parse_with: records errors on bad input" {
  let (_, errors) = parse_with("+", test_spec, test_tokenize, test_grammar)
  inspect(errors.length(), content="1")
  inspect(errors[0].message, content="expected number")
}
