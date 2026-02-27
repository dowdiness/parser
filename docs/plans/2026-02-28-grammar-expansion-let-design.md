# Design: Grammar Expansion — Expression-level `let` Binding

**Created:** 2026-02-28
**Status:** Approved

## Problem

The lambda calculus grammar currently parses exactly **one** expression per source string.
`Term`, `AstKind`, and `SyntaxKind` have no `let` binding — so nested variable binding
requires full lambda syntax (`(λx.body) init`), which is verbose and unreadable for
anything beyond trivial examples.

## Decision

Add expression-level `let x = e in body` as a first-class AST node (not desugared to
`App(Lam(...), ...)`). Non-recursive only. `SourceFile` stays a single-expression wrapper.

**Why first-class over desugar:** The CRDT editor needs to round-trip source ↔ AST cleanly.
Desugaring loses the `let` form before the pretty-printer, viz renderer, or future evaluator
can see it.

**Why expression-level over top-level declarations:** Top-level declarations require
rethinking `SourceFile` as a list of items and a new `TopLevel` AST concept — a larger
architectural change. Expression-level let is the minimal extension that makes the grammar
meaningfully more expressive.

## Grammar Rule

A new `parse_let_expr` function is inserted between the existing `parse_expression`
and `parse_binary_op` levels:

```
parse_expression → parse_let_expr
parse_let_expr:
  | LetKeyword IdentToken EqToken parse_let_expr InKeyword parse_let_expr  → LetExpr
  | parse_binary_op → parse_application → parse_atom
```

Both init and body call `parse_let_expr` recursively (right-recursive), so nested bindings
work without any special cases:

```
let x = 1 in let y = 2 in x + y
  → Let("x", Int(1), Let("y", Int(2), Bop(Plus, Var("x"), Var("y"))))
```

## Changes

### `src/token/token.mbt`

Add three variants to `Token`:
```moonbit
Let   // "let"
In    // "in"
Eq    // "="
```
Update `print_token` with matching cases.

### `src/syntax/syntax_kind.mbt`

Add four variants to `SyntaxKind`:

| Variant | `to_raw` integer | Role |
|---------|-----------------|------|
| `LetKeyword` | 23 | token kind |
| `InKeyword` | 24 | token kind |
| `EqToken` | 25 | token kind |
| `LetExpr` | 26 | node kind |

Update `is_token` (include the three new token kinds), `to_raw`, and `from_raw`.

### `src/lexer/lexer.mbt`

Two changes to `tokenize_helper`:
1. `'='` character branch → emit `Eq` token.
2. Identifier keyword match: add `"let" => @token.Token::Let` and `"in" => @token.Token::In`.

### `src/parser/cst_parser.mbt`

Add `parse_let_expr` between `parse_expression` and `parse_binary_op`:

```moonbit
// BEFORE
fn parse_expression(ctx) -> ... {
  parse_binary_op(ctx)
}

// AFTER
fn parse_expression(ctx) -> ... {
  parse_let_expr(ctx)
}

fn parse_let_expr(ctx) -> ... {
  if current token is LetKeyword:
    start_node(LetExpr)
    eat(LetKeyword)         // let
    eat_whitespace()
    eat(IdentToken)         // x
    eat_whitespace()
    eat(EqToken)            // =
    eat_whitespace()
    parse_let_expr(ctx)     // init (recursive)
    eat_whitespace()
    eat(InKeyword)          // in
    eat_whitespace()
    parse_let_expr(ctx)     // body (recursive)
    finish_node()
  else:
    parse_binary_op(ctx)
}
```

Error recovery: missing `in` or missing body should emit `ErrorToken` and continue,
consistent with how `IfExpr` handles missing `then`/`else`.

### `src/ast/ast.mbt`

Add `Let` to both enums:
```moonbit
// Term enum
Let(VarName, Term, Term)  // let x = init in body

// AstKind enum
Let(String)  // name; children[0] = init, children[1] = body
```

Update three functions with `Let` arms mirroring the existing `If` / `Lam` patterns:
- `print_ast_node` → `"let " + name + " = " + go(init) + " in " + go(body)`
- `print_term` → same format
- `node_to_term` → `Term::Let(name, node_to_term(children[0]), node_to_term(children[1]))`

### `src/parser/cst_convert.mbt`

Add `@syntax.LetExpr` arm in `convert_syntax_node`, mirroring `IfExpr`:

```moonbit
@syntax.LetExpr => {
  let name = node.find_token(@syntax.IdentToken.to_raw())
    .map(t => t.text()).unwrap_or("")
  let (tight_start, _) = node.tight_span(trivia_kind=Some(ws))
  let children : Array[@ast.AstNode] = []
  for child in node.children() {
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

## What Does NOT Change

- `parse_binary_op`, `parse_application`, `parse_atom` — untouched
- `SourceFile` — still wraps a single expression
- `ReuseCursor`, `DamageTracker`, `TokenBuffer` — incremental layer unaffected
- `ParserDb` pipeline — no changes (AST equality check already ignores positions)
- All existing tests must continue to pass

## Success Criteria

- `moon test` passes; new let tests added covering:
  - Simple binding: `let x = 1 in x`
  - Nested: `let x = 1 in let y = 2 in x + y`
  - Let + application: `let f = λx.x in f 42`
  - Let + binary: `let x = 3 in x + 1`
  - Error recovery: `let x = 1` (missing `in body`)
- `moon check` clean
- No references to `EqToken`, `LetKeyword`, `InKeyword`, `LetExpr` missing from any of the 6 files
- `=` outside a `let` binding is still emitted as `ErrorToken` by the parser
