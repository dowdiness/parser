# Grammar Expansion: Expression-level `let` Binding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `let x = e in body` as a first-class expression form to the lambda calculus grammar, producing a `Let(VarName, Term, Term)` term and `AstKind::Let(String)` positioned node.

**Architecture:** New `parse_let_expr` function inserted between `parse_expression` and
`parse_binary_op` (Approach A). Six files touched in dependency order. Token and SyntaxKind
enum extensions have no test files of their own — they are verified with `moon check` and
exercised by the downstream lexer/parser tests. All other tasks are TDD: failing test →
implement → passing test → commit.

**Tech Stack:** MoonBit (`moon test`, `moon check`, `moon info && moon fmt`)

---

### Task 1: Add new Token and SyntaxKind variants

**Files:**
- Modify: `src/token/token.mbt`
- Modify: `src/syntax/syntax_kind.mbt`

**Step 1: Add three variants to the `Token` enum in `src/token/token.mbt`**

After the `Else // else` line (line 11), insert:
```moonbit
  Let // let
  In  // in
  Eq  // =
```

Add three cases to `print_token` (after the `Else => "else"` line):
```moonbit
    Let => "let"
    In => "in"
    Eq => "="
```

**Step 2: Add four variants to `SyntaxKind` in `src/syntax/syntax_kind.mbt`**

After `SourceFile` in the enum body, add:
```moonbit
  LetKeyword
  InKeyword
  EqToken
  LetExpr
```

In `is_token`, add three new token kinds to the `true` arm (after `EofToken`):
```moonbit
    | LetKeyword
    | InKeyword
    | EqToken => true
```

In `to_raw`, add four new cases (after `SourceFile => 22`):
```moonbit
    LetKeyword => 23
    InKeyword => 24
    EqToken => 25
    LetExpr => 26
```

In `from_raw`, add four new cases (after `22 => SourceFile`):
```moonbit
    23 => LetKeyword
    24 => InKeyword
    25 => EqToken
    26 => LetExpr
```

**Step 3: Run `moon check`**

```bash
moon check 2>&1
```
Expected: clean, no errors. No tests reference the new variants yet.

**Step 4: Commit**

```bash
git add src/token/token.mbt src/syntax/syntax_kind.mbt
git commit -m "feat: add Let/In/Eq tokens and LetKeyword/InKeyword/EqToken/LetExpr SyntaxKinds"
```

---

### Task 2: Lex `let`, `in`, and `=`

**Files:**
- Modify: `src/lexer/lexer.mbt`
- Modify: `src/lexer/lexer_test.mbt`

**Step 1: Write failing tests in `src/lexer/lexer_test.mbt`**

```moonbit
///|
test "tokenize let keyword" {
  let tokens = tokenize("let") catch { _ => abort("tokenize failed") }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("let"), content="true")
  inspect(s.contains("EOF"), content="true")
}

///|
test "tokenize in keyword" {
  let tokens = tokenize("in") catch { _ => abort("tokenize failed") }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("in"), content="true")
}

///|
test "tokenize eq" {
  let tokens = tokenize("=") catch { _ => abort("tokenize failed") }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("="), content="true")
}

///|
test "tokenize let expression" {
  let tokens = tokenize("let x = 1 in x") catch {
    _ => abort("tokenize failed")
  }
  let s = @token.print_token_infos(tokens)
  inspect(s.contains("let"), content="true")
  inspect(s.contains("in"), content="true")
  inspect(s.contains("="), content="true")
}
```

**Step 2: Run to verify they fail**

```bash
moon test -p dowdiness/parser/src/lexer -f lexer_test.mbt 2>&1
```
Expected: FAIL — `let`, `in`, `=` are not yet recognized by the lexer.

**Step 3: Implement in `src/lexer/lexer.mbt`**

In `tokenize_helper`, add a `'='` branch before the `Some(c)` catch-all (after the `Some('-')` block, around line 111):
```moonbit
      Some('=') => {
        acc.push(@token.TokenInfo::new(@token.Eq, pos, pos + 1))
        tokenize_helper(input, pos + 1, acc)
      }
```

In the identifier keyword match (around line 116–119), add two cases after `"else"`:
```moonbit
            "let" => @token.Token::Let
            "in" => @token.Token::In
```

**Step 4: Run the new tests**

```bash
moon test -p dowdiness/parser/src/lexer -f lexer_test.mbt 2>&1
```
Expected: all four new tests pass.

**Step 5: Run full suite**

```bash
moon test 2>&1 | tail -5
```
Expected: same passing count as before (no regressions — no existing test uses `in`/`let`/`=`).

**Step 6: Commit**

```bash
git add src/lexer/lexer.mbt src/lexer/lexer_test.mbt
git commit -m "feat: lex let/in keywords and = operator"
```

---

### Task 3: Grammar — `parse_let_expr` rule

**Files:**
- Modify: `src/parser/cst_parser.mbt`
- Modify: `src/parser/cst_tree_test.mbt`

**Step 1: Write failing CST tests in `src/parser/cst_tree_test.mbt`**

```moonbit
///|
test "cst: let expression" {
  let cst = parse_cst("let x = 1 in x") catch { _ => abort("parse failed") }
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LetExpr")
}

///|
test "cst: nested let" {
  let cst = parse_cst("let x = 1 in let y = 2 in x") catch {
    _ => abort("parse failed")
  }
  let child = match cst.children[0] {
    @seam.CstElement::Node(n) => n
    @seam.CstElement::Token(_) => abort("Expected node, got token")
  }
  inspect(@syntax.SyntaxKind::from_raw(child.kind), content="LetExpr")
}
```

**Step 2: Run to verify they fail**

```bash
moon test -p dowdiness/parser/src/parser -f cst_tree_test.mbt 2>&1
```
Expected: FAIL — `let` is currently unrecognized and falls to error recovery.

**Step 3: Implement in `src/parser/cst_parser.mbt`**

**(a)** Update `at_stop_token` to treat `In` as a boundary (prevents error recovery from consuming `in` when it appears unexpectedly):

```moonbit
fn at_stop_token(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  match ctx.peek() {
    @token.RightParen | @token.Then | @token.Else | @token.In | @token.EOF =>
      true
    _ => false
  }
}
```

**(b)** Change `parse_expression` to call `parse_let_expr` instead of `parse_binary_op`:

```moonbit
fn parse_expression(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  parse_let_expr(ctx)
}
```

**(c)** Add `parse_let_expr` after `parse_expression` and before `parse_binary_op`:

```moonbit
///|
fn parse_let_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  match ctx.peek() {
    @token.Let =>
      ctx.node(@syntax.LetExpr, fn() {
        ctx.emit_token(@syntax.LetKeyword)
        match ctx.peek() {
          @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
          _ => {
            ctx.error("Expected variable name after 'let'")
            ctx.emit_error_placeholder()
          }
        }
        lambda_expect(ctx, @token.Eq, @syntax.EqToken)
        parse_let_expr(ctx)
        lambda_expect(ctx, @token.In, @syntax.InKeyword)
        parse_let_expr(ctx)
      })
    _ => parse_binary_op(ctx)
  }
}
```

**Step 4: Run the new CST tests**

```bash
moon test -p dowdiness/parser/src/parser -f cst_tree_test.mbt 2>&1
```
Expected: both new tests pass.

**Step 5: Run full suite**

```bash
moon test 2>&1 | tail -5
```
Expected: no regressions.

**Step 6: Commit**

```bash
git add src/parser/cst_parser.mbt src/parser/cst_tree_test.mbt
git commit -m "feat: add parse_let_expr grammar rule"
```

---

### Task 4: AST — `Let` variant in `Term` and `AstKind`

**Files:**
- Modify: `src/ast/ast.mbt`

There is no separate test file for `ast.mbt` — the Let variant is exercised by the end-to-end
parser tests in Task 5. MoonBit's exhaustiveness checker will catch any missing match arms
after the enum additions, so `moon check` serves as verification here.

**Step 1: Add `Let` to the `Term` enum** (after the `If` line):
```moonbit
  // Let binding (non-recursive)
  Let(VarName, Term, Term)
```

**Step 2: Add `Let` to the `AstKind` enum** (after the `If` line):
```moonbit
  Let(String) // Let binding (name; init=children[0], body=children[1])
```

**Step 3: Add `Let` arm to `print_ast_node`** (inside the `go` function, after `AstKind::If`):
```moonbit
      AstKind::Let(name) => {
        let init = if n.children.length() > 0 { go(n.children[0]) } else { "?" }
        let body = if n.children.length() > 1 { go(n.children[1]) } else { "?" }
        "let " + name + " = " + init + " in " + body
      }
```

**Step 4: Add `Let` arm to `print_term`** (inside the `go` function, after `If`):
```moonbit
      Let(x, init, body) => "let " + x + " = " + go(init) + " in " + go(body)
```

**Step 5: Add `Let` arm to `node_to_term`** (after the `AstKind::If` arm):
```moonbit
    AstKind::Let(name) => {
      let init = if node.children.length() > 0 {
        node_to_term(node.children[0])
      } else {
        abort("Let node missing init child")
      }
      let body = if node.children.length() > 1 {
        node_to_term(node.children[1])
      } else {
        abort("Let node missing body child")
      }
      Term::Let(name, init, body)
    }
```

**Step 6: Run `moon check`**

```bash
moon check 2>&1
```
Expected: clean — the compiler will flag any exhaustiveness gaps.

**Step 7: Commit**

```bash
git add src/ast/ast.mbt
git commit -m "feat: add Let variant to Term and AstKind"
```

---

### Task 5: CST→AST conversion for `LetExpr` + end-to-end tests

**Files:**
- Modify: `src/parser/cst_convert.mbt`
- Modify: `src/parser/parser_test.mbt`

**Step 1: Write failing end-to-end tests in `src/parser/parser_test.mbt`**

```moonbit
///|
test "parse let expression" {
  let expr = parse("let x = 1 in x") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(expr), content="let x = 1 in x")
}

///|
test "parse let with binary op in body" {
  let expr = parse("let x = 3 in x + 1") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(expr), content="let x = 3 in (x + 1)")
}

///|
test "parse nested let" {
  let expr = parse("let x = 1 in let y = 2 in x + y") catch {
    _ => abort("parse failed")
  }
  inspect(@ast.print_term(expr), content="let x = 1 in let y = 2 in (x + y)")
}

///|
test "parse let with lambda" {
  let expr = parse("let f = λx.x in f 42") catch { _ => abort("parse failed") }
  inspect(@ast.print_term(expr), content="let f = (λx. x) in (f 42)")
}
```

**Step 2: Run to verify they fail**

```bash
moon test -p dowdiness/parser/src/parser -f parser_test.mbt 2>&1
```
Expected: FAIL — `LetExpr` hits the `_ => AstNode::error(...)` fallback in `convert_syntax_node`.

**Step 3: Add `LetExpr` arm in `src/parser/cst_convert.mbt`**

Inside `convert_syntax_node`, add after the `@syntax.IfExpr` arm and before `@syntax.ParenExpr`:

```moonbit
    @syntax.LetExpr => {
      let name = node
        .find_token(@syntax.IdentToken.to_raw())
        .map(t => t.text())
        .unwrap_or("")
      let (tight_start, _) = node.tight_span(trivia_kind=Some(ws))
      let children : Array[@ast.AstNode] = []
      let syntax_children = node.children()
      for child in syntax_children {
        children.push(convert_syntax_node(child, counter))
      }
      let let_end = if children.length() > 0 {
        children[children.length() - 1].end
      } else {
        node.end()
      }
      @ast.AstNode::new(
        @ast.AstKind::Let(name),
        tight_start,
        let_end,
        next_id(),
        children,
      )
    }
```

**Step 4: Run the end-to-end tests**

```bash
moon test -p dowdiness/parser/src/parser -f parser_test.mbt 2>&1
```
Expected: all four new tests pass.

**Step 5: Run full suite**

```bash
moon test 2>&1 | tail -5
```
Expected: `Total tests: N, passed: N, failed: 0` — all prior tests still pass, new let tests added.

**Step 6: Commit**

```bash
git add src/parser/cst_convert.mbt src/parser/parser_test.mbt
git commit -m "feat: CST→AST conversion for LetExpr"
```

---

### Task 6: Regenerate interfaces, update docs, archive plan

**Files:**
- Auto-updated: `*.mbti` interface files
- Modify: `docs/plans/2026-02-28-grammar-expansion-let-design.md`
- Modify: `docs/README.md`

**Step 1: Regenerate interfaces and format**

```bash
moon info && moon fmt
```

**Step 2: Verify clean**

```bash
moon check 2>&1
bash check-docs.sh 2>&1
```
Both must be clean.

**Step 3: Mark design doc complete**

In `docs/plans/2026-02-28-grammar-expansion-let-design.md`, change `**Status:** Approved` to `**Status:** Complete`.

**Step 4: Move design doc to archive**

```bash
git mv docs/plans/2026-02-28-grammar-expansion-let-design.md docs/archive/completed-phases/
```

**Step 5: Update `docs/README.md`**

Remove from Active Plans:
```markdown
- [plans/2026-02-28-grammar-expansion-let-design.md](plans/2026-02-28-grammar-expansion-let-design.md) — design for expression-level `let` binding
```

The archive section already links to `archive/completed-phases/` — no line-level change needed there.

**Step 6: Run `bash check-docs.sh`**

```bash
bash check-docs.sh 2>&1
```
Expected: all checks pass (line count ≤60, no active plan with Status:Complete).

**Step 7: Final commit**

```bash
git add docs/ *.mbti src/*/pkg.generated.mbti
git commit -m "chore: regenerate interfaces and archive grammar-expansion-let plan"
```
