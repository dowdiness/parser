// Phase 3: Integrated Error Recovery Tests
//
// These tests verify the Phase 3 exit criteria from ROADMAP.md:
// 1. Parser produces partial trees for all error test cases
// 2. Multiple errors reported for inputs with multiple problems
// 3. Parser never panics or enters infinite loop on any input
// 4. All valid inputs still parse identically to current behavior
// 5. Fuzzing with random inputs: parser always terminates, always produces a tree

// ============================================================================
// Section 1: Partial Tree Construction
// ============================================================================

///|
test "phase3: missing lambda parameter produces partial lambda" {
  let (tree, errors) = parse_with_error_recovery("λ.x")
  // Should have error but still produce LambdaExpr
  inspect(errors.length() > 0, content="true")
  inspect(tree.kind is @term.TermKind::Lam(_), content="true")
}

///|
test "phase3: missing lambda body produces partial lambda" {
  let (tree, errors) = parse_with_error_recovery("λx.")
  // Should have error for missing body, but still produce lambda structure
  inspect(errors.length() > 0, content="true")
  inspect(tree.kind is @term.TermKind::Lam(_), content="true")
}

///|
test "phase3: unexpected operator in lambda body - recovery continues" {
  let (tree, errors) = parse_with_error_recovery("λx. + y")
  // Should produce lambda with error in body, then continue to parse y
  inspect(errors.length(), content="1")
  inspect(tree.kind is @term.TermKind::Lam(_), content="true")
  // Body should have application containing error and y
  inspect(has_errors(tree), content="true")
}

///|
test "phase3: unclosed paren produces partial ParenExpr" {
  let (tree, errors) = parse_with_error_recovery("(x + y")
  // Should report missing ), but parse the inner expression
  inspect(errors.length() > 0, content="true")
  inspect(tree.end > 0, content="true")
}

///|
test "phase3: missing if condition" {
  let (tree, errors) = parse_with_error_recovery("if then y else z")
  // Should report error but still produce IfExpr structure
  inspect(errors.length() > 0, content="true")
  inspect(tree.kind is @term.TermKind::If, content="true")
}

///|
test "phase3: missing then branch" {
  let (tree, errors) = parse_with_error_recovery("if x else z")
  // Should report missing then
  inspect(errors.length() > 0, content="true")
  inspect(tree.kind is @term.TermKind::If, content="true")
}

///|
test "phase3: missing else branch" {
  let (tree, errors) = parse_with_error_recovery("if x then y")
  // Should report missing else
  inspect(errors.length() > 0, content="true")
  inspect(tree.kind is @term.TermKind::If, content="true")
}

// ============================================================================
// Section 2: Multiple Error Reporting
// ============================================================================

///|
test "phase3: two errors - missing param and extra token" {
  let (tree, errors) = parse_with_error_recovery("λ.x )")
  // Should report: missing param, extra token after expression
  inspect(errors.length() >= 2, content="true")
  inspect(has_errors(tree), content="true")
}

///|
test "phase3: three errors - complex malformed input" {
  let (tree, errors) = parse_with_error_recovery("λ. + ) x")
  // Should report: missing param, unexpected +, extra tokens
  inspect(errors.length() >= 2, content="true")
  inspect(has_errors(tree), content="true")
}

///|
test "phase3: error in each clause of if" {
  let (tree, errors) = parse_with_error_recovery("if + then + else +")
  // Each + is unexpected, should get multiple errors
  inspect(errors.length() >= 3, content="true")
  inspect(tree.kind is @term.TermKind::If, content="true")
}

///|
test "phase3: nested errors" {
  let (tree, errors) = parse_with_error_recovery("(λ.x (+ y))")
  // Missing param in lambda, unexpected + in inner paren
  inspect(errors.length() >= 2, content="true")
  inspect(has_errors(tree), content="true")
}

// ============================================================================
// Section 3: Termination Guarantees (Random Input Fuzzing)
// ============================================================================

// Note: The lexer does NOT do error recovery - invalid characters like '@' cause
// tokenization failure which short-circuits parsing entirely. This is by design.
// These tests use only lexer-valid tokens to test parser-level error recovery.

///|
fn phase3_lcg_next(seed : Int) -> Int {
  let a = 1664525
  let c = 1013904223
  // Use a mask to keep within positive 31-bit range
  (seed * a + c) & 0x7FFFFFFF
}

///|
fn phase3_random_token(seed : Int) -> (String, Int) {
  let next = phase3_lcg_next(seed)
  // Pool of valid tokens (no invalid chars that would fail lexer)
  let tokens = [
    "x", "y", "z", "a", "b", "f", "g", "0", "1", "2", "42", "99", "if", "then", "else",
    "\\", "λ", ".", "(", ")", "+", "-", " ", "  ",
  ]
  let idx = (next & 0x7FFFFFFF) % tokens.length()
  (tokens[idx], next)
}

///|
fn phase3_random_string(seed : Int, token_count : Int) -> String {
  let mut s = seed
  let mut result = ""
  for _i = 0; _i < token_count; _i = _i + 1 {
    let (token, next) = phase3_random_token(s)
    result = result + token
    s = next
  }
  result
}

///|
test "phase3-fuzz: random token inputs terminate" {
  // Generate 100 random strings and verify parser terminates
  let mut seed = 42
  for _i = 0; _i < 100; _i = _i + 1 {
    let input = phase3_random_string(seed, 30)
    seed = phase3_lcg_next(seed)

    // Parser must terminate and produce a tree (possibly with errors)
    let (tree, _errors) = parse_with_error_recovery(input)

    // Tree must be valid (has a node_id)
    assert_true(tree.node_id >= 0)
  }
}

///|
test "phase3-fuzz: very long random inputs terminate" {
  // Test with longer inputs to stress error budget
  let mut seed = 12345
  for _i = 0; _i < 20; _i = _i + 1 {
    let input = phase3_random_string(seed, 100)
    seed = phase3_lcg_next(seed)
    let (tree, _errors) = parse_with_error_recovery(input)
    assert_true(tree.node_id >= 0)
  }
}

///|
test "phase3-fuzz: pathological repeated operators" {
  // Input designed to hit error budget: repeated unexpected operators
  let input = "+ + + + + + + + + + + + + + + + + + + + + + + + + + + + + +"
  let (tree, _errors) = parse_with_error_recovery(input)
  // Should terminate (error budget prevents infinite loop)
  assert_true(tree.node_id >= 0)
}

///|
test "phase3-fuzz: alternating valid/invalid constructs" {
  // Stress recovery by alternating operators and identifiers in wrong places
  let input = "+ x + y + z + if + then + else +"
  let (tree, errors) = parse_with_error_recovery(input)
  // Should produce tree with multiple errors
  assert_true(tree.node_id >= 0)
  assert_true(errors.length() > 0)
}

///|
test "phase3-fuzz: deeply nested parens with errors" {
  let input = "(((((( + x )))))))"
  let (tree, errors) = parse_with_error_recovery(input)
  assert_true(tree.node_id >= 0)
  assert_true(errors.length() > 0)
}

///|
test "phase3-fuzz: lambda chain with errors" {
  let input = "λa.λb.λc.λd.λe. + x"
  let (tree, errors) = parse_with_error_recovery(input)
  assert_true(tree.node_id >= 0)
  assert_true(errors.length() > 0)
}

// ============================================================================
// Section 4: Valid Input Identity (Regression)
// ============================================================================

///|
test "phase3: valid inputs unchanged - comprehensive" {
  let inputs = [
    "0", "42", "123456789", "x", "abc", "variable123", "λx.x", "\\x.x", "λa.λb.a",
    "f x", "f x y z", "1 + 2", "1 - 2", "1 + 2 - 3 + 4", "if x then 1 else 2", "if 1 then if 2 then 3 else 4 else 5",
    "(x)", "((x))", "(λx.x) 42", "λf.λx.f (f x)", "λm.λn.λf.λx.m f (n f x)",
    "(1 + 2) - 3",
  ]
  for input in inputs {
    let direct = parse_tree(input)
    let (recovered, errors) = parse_with_error_recovery(input)

    // No errors on valid input
    if errors.length() != 0 {
      abort("Unexpected error on valid input: \{input}, errors: \{errors}")
    }

    // Trees must match
    let direct_str = @term.print_term_node(direct)
    let recovered_str = @term.print_term_node(recovered)
    if direct_str != recovered_str {
      abort("Mismatch on valid input: \{input}")
    }
  }
}

// ============================================================================
// Section 5: Error Recovery Continues After Sync Points
// ============================================================================

// Note: Using valid tokens that are unexpected in context, not invalid chars.
// The lexer doesn't do error recovery - it fails on invalid characters.

///|
test "phase3: recovery at right paren" {
  // Error (unexpected +) before ), then valid expression follows
  let (tree, errors) = parse_with_error_recovery("(+) x")
  assert_true(errors.length() > 0)
  // Should parse the x after the paren - tree should cover significant content
  assert_true(tree.end >= 4)
}

///|
test "phase3: recovery at lambda" {
  // Error (leading +) then lambda should be parsed
  let (tree, errors) = parse_with_error_recovery("+ λx.x")
  assert_true(errors.length() > 0)
  // Should have the lambda in the tree (application of error and lambda)
  assert_true(has_errors(tree))
  assert_true(tree.end >= 6)
}

///|
test "phase3: recovery at if" {
  // Error (leading +) then if should work
  let (tree, errors) = parse_with_error_recovery("+ if x then y else z")
  assert_true(errors.length() > 0)
  // Tree should contain the if expression
  assert_true(tree.end >= 10)
}

///|
test "phase3: multiple sync point recoveries" {
  // Multiple parse errors, parser should recover and continue
  let (tree, errors) = parse_with_error_recovery(
    "+ ) λx.x + + if 1 then 2 else 3",
  )
  assert_true(errors.length() > 0)
  // Parser should have recovered and parsed significant content
  assert_true(tree.end > 10)
}
