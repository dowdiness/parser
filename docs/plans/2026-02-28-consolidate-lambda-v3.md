# Consolidate Lambda Package + Generic IncrementalParser (v3)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move all lambda-specific code from `src/parser/` into `src/lambda/`. Make
`src/incremental/` and the adapter layer in `src/parser/` fully generic by extending
`@core.LanguageSpec[T, K]` with a `parse_root` field and adding a generic
`parse_tokens_indexed` driver to `@core`. After this change:
- `src/parser/` is deleted (empty — adapter code moves to `@core`)
- `src/incremental/` depends only on `@core` and `@seam`
- `src/lambda/` is the single home for all lambda language code

**Architecture:** `@core` gains a `parse_tokens_indexed[T, K]` function (the generic
incremental parse driver) and `LanguageSpec` gains a `parse_root` field. The lambda grammar
functions (`parse_lambda_root`, etc.) live in `src/lambda/` and are wired into `lambda_spec`
as `parse_root`. `@incremental.IncrementalParser[@Ast]` uses an `IncrementalLanguage[@Ast]`
vtable (mirroring `@pipeline.Language[@Ast]`).

**Tech Stack:** MoonBit, `moon` build tool

---

## Package Dependency Map

```text
Before:
  src/parser/     ← token, syntax, ast, lexer, core, seam   (lambda grammar + adapters)
  src/lambda/     ← pipeline, lexer, @parse, ast, viz       (thin glue)
  src/incremental/← @parse, token, ast, lexer, core, seam   (lambda-specific)
  src/benchmarks/ ← @parse, @lambda, @incremental, lexer, core

After:
  src/core/       gains parse_tokens_indexed + LanguageSpec::parse_root
  src/lambda/     ← pipeline, lexer, token, syntax, ast, core, seam, viz, strconv, @incremental
  src/incremental/← core, seam                              (generic only)
  src/benchmarks/ ← @lambda, @incremental, core
  src/parser/     ← DELETED
```

---

## Separation Boundary: What Goes in @core vs @lambda

**The enforced rule:** `@core` must compile with **zero** imports of `@token`, `@syntax`,
`@ast`, or `@lexer`. The MoonBit module graph makes this physically verifiable:
```bash
grep -n "token\|syntax\|ast\|lexer" src/core/moon.pkg
# → zero results (enforced by build system, not convention)
```

`LanguageSpec[T, K]` is the **only** channel through which language behavior enters
`@core`. Every lambda-specific constant or function either:
(a) lives in `@lambda` and gets wired into a `LanguageSpec` field, or
(b) is already abstractly represented in `LanguageSpec` as a generic `T`/`K`/`RawKind`.

| Item | Where | Why |
|------|-------|-----|
| `parse_lambda_root`, `parse_expression`, `parse_let_expr`, … | `@lambda` | Grammar rules reference `@token.Token` and `@syntax.SyntaxKind` directly |
| `lambda_spec : LanguageSpec[Token, SyntaxKind]` | `@lambda` | Binds the two lambda-specific concrete types to the generic spec |
| `make_reuse_cursor` | `@lambda` | References `Array[@token.TokenInfo]` — lambda-specific token layout |
| `parse_cst_recover`, `parse_cst_recover_with_tokens` | `@lambda` | Call `@lexer.tokenize` — lambda's tokenizer |
| `syntax_node_to_ast_node` | `@lambda` | Converts `SyntaxNode` → `@ast.AstNode` |
| `parse_tokens_indexed[T, K]` | `@core` | Indexed closures only; delegates to `spec.parse_root(ctx)` |
| `build_tree_generic[T, K]` | `@core` | Uses `spec.whitespace_kind` and `spec.root_kind` — already in `LanguageSpec` |
| `LanguageSpec::parse_root` | `@core` | Grammar entry point; type is `(ParserContext[T, K]) -> Unit` — no `@lambda` types |
| `ReuseCursor::new` | `@core` | Accepts indexed closures; no `@token`/`@syntax` references |

**`parse_with` vs `parse_tokens_indexed` coexist by design:**
- `parse_with(tokens, source, grammar, spec)` — grammar as explicit parameter; used in
  `@core` whitebox tests where `test_spec.parse_root` is a no-op.
- `parse_tokens_indexed(...)` — grammar from `spec.parse_root`; used in production pipeline.

Both are public. Neither replaces the other.

---

## seam module location

`seam` lives at **`./seam/`** (repo root) — a separate MoonBit module declared in
`moon.mod.json` as `"dowdiness/seam": { "path": "seam" }`. It is NOT inside `src/`.
Import alias is `@seam` throughout.

---

## Task 1: Extend @core with parse_root + parse_tokens_indexed

No behavior changes. Two files modified, new function added.

**Files:**
- Modify: `src/core/lib.mbt`
- Modify: `src/core/lib_wbtest.mbt`

**Step 1: Add parse_root field to LanguageSpec in src/core/lib.mbt**

In the `LanguageSpec[T, K]` struct definition (after the last existing field), add:

```moonbit
  // Grammar entry point. Called by parse_tokens_indexed to drive the full parse.
  // Receives a fully-configured ParserContext and must call flush_trivia before
  // returning. Set to a no-op by default for call sites (e.g. tests) that use
  // parse_with() with an explicit grammar parameter instead.
  parse_root : (ParserContext[T, K]) -> Unit
```

**Step 2: Update LanguageSpec::new constructor**

Add a labeled parameter with a no-op default **before** the closing `)`:

```moonbit
  parse_root? : (ParserContext[T, K]) -> Unit = fn(_) { () },
```

And add `parse_root` to the struct literal returned at the end of `LanguageSpec::new`.

**Step 3: Update test struct literals in src/core/lib.mbt**

There are two direct `LanguageSpec[String, Int]` struct literals in the test section
(in `make_test_fixtures` around line 785 and the trivia test around line 829).
Both need the new field added. In each literal, add:

```moonbit
  parse_root: fn(_) { () },
```

**Step 4: Add private build_tree_generic helper**

Add this private function to `src/core/lib.mbt` (after `select_build_tree` would have been,
near the bottom of the production code section before the tests):

```moonbit
///|
/// Build the CST from an event buffer using spec metadata for root and trivia kinds.
/// Generic replacement for the lambda-specific select_build_tree in src/parser/.
fn[T, K] build_tree_generic(
  buf : @seam.EventBuffer,
  spec : LanguageSpec[T, K],
  interner : @seam.Interner?,
  node_interner : @seam.NodeInterner?,
) -> @seam.CstNode {
  let ws = (spec.kind_to_raw)(spec.whitespace_kind)
  let root = (spec.kind_to_raw)(spec.root_kind)
  match (interner, node_interner) {
    (Some(i), Some(ni)) =>
      buf.build_tree_fully_interned(root, i, ni, trivia_kind=Some(ws))
    (Some(i), None) => buf.build_tree_interned(root, i, trivia_kind=Some(ws))
    _ => buf.build_tree(root, trivia_kind=Some(ws))
  }
}
```

**Step 5: Add parse_tokens_indexed public function**

Add this function to `src/core/lib.mbt` (after `parse_with`):

```moonbit
///|
/// Generic incremental parse driver. Replaces the lambda-specific
/// `run_parse` / `run_parse_incremental` pair in `src/parser/`.
///
/// Accepts indexed token accessors (avoids O(n) Array[TokenInfo[T]] allocation
/// when the caller already has tokens in a language-specific layout).
/// Uses `spec.parse_root` as the grammar entry point.
///
/// Returns `(CstNode, diagnostics, reuse_count)`.
/// reuse_count is 0 for non-incremental calls (cursor=None).
pub fn[T, K] parse_tokens_indexed(
  source : String,
  token_count : Int,
  get_token : (Int) -> T,
  get_start : (Int) -> Int,
  get_end : (Int) -> Int,
  spec : LanguageSpec[T, K],
  cursor~ : ReuseCursor[T, K]? = None,
  prev_diagnostics~ : Array[Diagnostic[T]]? = None,
  interner~ : @seam.Interner? = None,
  node_interner~ : @seam.NodeInterner? = None,
) -> (@seam.CstNode, Array[Diagnostic[T]], Int) {
  let ctx = ParserContext::new_indexed(
    token_count, get_token, get_start, get_end, source, spec,
  )
  match cursor {
    Some(c) => {
      ctx.set_reuse_cursor(c)
      match prev_diagnostics {
        Some(prev) => ctx.set_reuse_diagnostics(prev)
        None => ()
      }
    }
    None => ()
  }
  (spec.parse_root)(ctx)
  ctx.flush_trivia()
  if ctx.open_nodes != 0 {
    abort(
      "parse_tokens_indexed: grammar left " +
      ctx.open_nodes.to_string() +
      " unclosed nodes",
    )
  }
  (
    build_tree_generic(ctx.events, spec, interner, node_interner),
    ctx.errors,
    ctx.reuse_count,
  )
}
```

**Step 6: Update test_spec struct literal in src/core/lib_wbtest.mbt**

`test_spec` is constructed as a direct struct literal (line ~76). Add the new field:

```moonbit
  parse_root: fn(_) { () },
```

Note: `parse_with` in `lib_wbtest.mbt` tests pass `test_grammar` explicitly as a separate
parameter, so `test_spec.parse_root` is never called in those tests. The no-op is correct.

**Step 7: Verify moon check and tests**

```bash
moon check
moon test
```

Expected: same pass count (371), zero failures. No behavior changed — only new type/function added.

**Step 8: Commit**

```bash
git add src/core/lib.mbt src/core/lib_wbtest.mbt
git commit -m "feat(core): add LanguageSpec::parse_root + parse_tokens_indexed generic driver"
```

---

## Task 2: Move src/parser/ production files to src/lambda/, rewrite adapter

The moved files are rewritten — not just copied. `cst_parser.mbt` changes the most: the
adapter functions (`run_parse`, `run_parse_incremental`, `select_build_tree`) are deleted
and replaced by calls to `@core.parse_tokens_indexed`. The grammar rules stay intact.

**Files:**
- Modify: `src/lambda/moon.pkg`
- Move (rewritten): `src/parser/cst_parser.mbt` → `src/lambda/cst_parser.mbt`
- Copy (verbatim): `src/parser/lambda_spec.mbt` → `src/lambda/lambda_spec.mbt`
- Copy (verbatim): `src/parser/cst_convert.mbt` → `src/lambda/cst_convert.mbt`
- Copy (verbatim): `src/parser/parser.mbt`       → `src/lambda/parser.mbt`
- Copy (verbatim): `src/parser/error_recovery.mbt` → `src/lambda/error_recovery.mbt`

**Step 1: Update src/lambda/moon.pkg**

```toml
import {
  "dowdiness/parser/pipeline" @pipeline,
  "dowdiness/parser/lexer",
  "dowdiness/parser/ast",
  "dowdiness/parser/viz" @viz,
  "dowdiness/parser/token",
  "dowdiness/parser/syntax",
  "dowdiness/parser/core" @core,
  "dowdiness/seam" @seam,
  "moonbitlang/core/strconv",
}

import {
  "moonbitlang/core/quickcheck",
} for "test"
```

**Step 2: Copy verbatim files**

```bash
cp src/parser/lambda_spec.mbt     src/lambda/lambda_spec.mbt
cp src/parser/cst_convert.mbt     src/lambda/cst_convert.mbt
cp src/parser/parser.mbt          src/lambda/parser.mbt
cp src/parser/error_recovery.mbt  src/lambda/error_recovery.mbt
```

**Step 3: Add parse_root to lambda_spec in src/lambda/lambda_spec.mbt**

After copying, `src/lambda/lambda_spec.mbt` has the `lambda_spec` value. The LAST argument
to `@core.LanguageSpec::new(...)` currently ends with `cst_token_matches=(...)`. Add the
`parse_root` labeled argument before the closing `)`:

```moonbit
  parse_root=parse_lambda_root,
```

`parse_lambda_root` is defined in `cst_parser.mbt` (same package) — the mutual reference
works because both files are in the same package.

**Step 4: Write src/lambda/cst_parser.mbt (rewritten)**

The new file keeps all grammar rules and public parse API but replaces the adapter internals:

```moonbit
///|
const MAX_ERRORS : Int = 50

///|
/// Convert SyntaxKind to RawKind for concrete syntax tree events.
fn raw(kind : @syntax.SyntaxKind) -> @seam.RawKind {
  kind.to_raw()
}

///|
/// Create a ReuseCursor from an old syntax tree and a pre-tokenized new stream.
pub fn make_reuse_cursor(
  old_tree : @seam.CstNode,
  damage_start : Int,
  damage_end : Int,
  tokens : Array[@token.TokenInfo[@token.Token]],
) -> @core.ReuseCursor[@token.Token, @syntax.SyntaxKind] {
  @core.ReuseCursor::new(
    old_tree,
    damage_start,
    damage_end,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    lambda_spec,
  )
}

///|
/// Strict: raises ParseError on first syntax error (backward compat).
pub fn parse_cst(source : String) -> @seam.CstNode raise {
  let (cst, errors) = parse_cst_recover(source)
  if errors.length() > 0 {
    let diag = errors[0]
    raise ParseError(diag.message, diag.got_token)
  }
  cst
}

///|
/// Recovering: returns tree with ErrorNodes + diagnostic list.
/// Only raises for LexError (unrecoverable).
pub fn parse_cst_recover(
  source : String,
  interner? : @seam.Interner? = None,
  node_interner? : @seam.NodeInterner? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
  let tokens = @lexer.tokenize(source)
  let (cst, diagnostics, _) = @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    lambda_spec,
    interner=interner,
    node_interner=node_interner,
  )
  (cst, diagnostics)
}

///|
/// Parse with reuse cursor for incremental parsing with subtree reuse.
pub fn parse_cst_with_cursor(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind],
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    lambda_spec,
    cursor=Some(cursor),
    prev_diagnostics=prev_diagnostics,
  )
}

///|
/// Parse with pre-tokenized input and optional reuse cursor.
pub fn parse_cst_recover_with_tokens(
  source : String,
  tokens : Array[@token.TokenInfo],
  cursor : @core.ReuseCursor[@token.Token, @syntax.SyntaxKind]?,
  prev_diagnostics? : Array[@core.Diagnostic[@token.Token]]? = None,
  interner? : @seam.Interner? = None,
  node_interner? : @seam.NodeInterner? = None,
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]], Int) {
  @core.parse_tokens_indexed(
    source,
    tokens.length(),
    fn(i) { tokens[i].token },
    fn(i) { tokens[i].start },
    fn(i) { tokens[i].end },
    lambda_spec,
    cursor=cursor,
    prev_diagnostics=prev_diagnostics,
    interner=interner,
    node_interner=node_interner,
  )
}

// ─── Grammar helpers ──────────────────────────────────────────────────────────

///|
fn at_stop_token(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Bool {
  match ctx.peek() {
    @token.RightParen | @token.Then | @token.Else | @token.In | @token.EOF =>
      true
    _ => false
  }
}

///|
fn lambda_expect(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
  expected : @token.Token,
  kind : @syntax.SyntaxKind,
) -> Unit {
  let current = ctx.peek()
  match (current, expected) {
    (a, b) if a == b => ctx.emit_token(kind)
    _ => {
      ctx.error("Expected " + @token.print_token(expected))
      ctx.emit_error_placeholder()
    }
  }
}

// ─── Grammar (entry point + rules) ───────────────────────────────────────────

///|
/// Entry point — wired into lambda_spec as parse_root.
fn parse_lambda_root(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  parse_expression(ctx)
  match ctx.peek() {
    @token.EOF => ctx.flush_trivia()
    _ => {
      ctx.error("Unexpected tokens after expression")
      ctx.start_node(@syntax.ErrorNode)
      while ctx.peek() != @token.EOF {
        ctx.bump_error()
      }
      ctx.finish_node()
      ctx.flush_trivia()
    }
  }
}

///|
fn parse_expression(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  parse_let_expr(ctx)
}

///|
fn parse_let_expr(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  match ctx.peek() {
    @token.Let =>
      ctx.node(@syntax.LetExpr, () => {
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

///|
fn parse_binary_op(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  parse_application(ctx)
  match ctx.peek() {
    @token.Plus | @token.Minus =>
      ctx.wrap_at(mark, @syntax.BinaryExpr, fn() {
        while ctx.error_count < MAX_ERRORS {
          match ctx.peek() {
            @token.Plus => {
              ctx.emit_token(@syntax.PlusToken)
              parse_application(ctx)
            }
            @token.Minus => {
              ctx.emit_token(@syntax.MinusToken)
              parse_application(ctx)
            }
            _ => break
          }
        }
      })
    _ => ()
  }
}

///|
fn parse_application(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  let mark = ctx.mark()
  parse_atom(ctx)
  match ctx.peek() {
    @token.LeftParen
    | @token.Identifier(_)
    | @token.Integer(_)
    | @token.Lambda =>
      ctx.wrap_at(mark, @syntax.AppExpr, fn() {
        while ctx.error_count < MAX_ERRORS {
          match ctx.peek() {
            @token.LeftParen
            | @token.Identifier(_)
            | @token.Integer(_)
            | @token.Lambda => parse_atom(ctx)
            _ => break
          }
        }
      })
    _ => ()
  }
}

///|
fn parse_atom(
  ctx : @core.ParserContext[@token.Token, @syntax.SyntaxKind],
) -> Unit {
  if ctx.error_count >= MAX_ERRORS {
    return
  }
  match ctx.peek() {
    @token.Integer(_) =>
      ctx.node(@syntax.IntLiteral, fn() { ctx.emit_token(@syntax.IntToken) })
    @token.Identifier(_) =>
      ctx.node(@syntax.VarRef, fn() { ctx.emit_token(@syntax.IdentToken) })
    @token.Lambda =>
      ctx.node(@syntax.LambdaExpr, () => {
        ctx.emit_token(@syntax.LambdaToken)
        match ctx.peek() {
          @token.Identifier(_) => ctx.emit_token(@syntax.IdentToken)
          _ => {
            ctx.error("Expected parameter after λ")
            ctx.emit_error_placeholder()
          }
        }
        lambda_expect(ctx, @token.Dot, @syntax.DotToken)
        parse_expression(ctx)
      })
    @token.If =>
      ctx.node(@syntax.IfExpr, fn() {
        ctx.emit_token(@syntax.IfKeyword)
        parse_expression(ctx)
        lambda_expect(ctx, @token.Then, @syntax.ThenKeyword)
        parse_expression(ctx)
        lambda_expect(ctx, @token.Else, @syntax.ElseKeyword)
        parse_expression(ctx)
      })
    @token.LeftParen =>
      ctx.node(@syntax.ParenExpr, fn() {
        ctx.emit_token(@syntax.LeftParenToken)
        parse_expression(ctx)
        lambda_expect(ctx, @token.RightParen, @syntax.RightParenToken)
      })
    _ => {
      ctx.error("Unexpected token")
      if at_stop_token(ctx) {
        ctx.start_node(@syntax.ErrorNode)
        ctx.emit_error_placeholder()
        ctx.finish_node()
      } else {
        ctx.start_node(@syntax.ErrorNode)
        ctx.bump_error()
        ctx.finish_node()
      }
    }
  }
}
```

**Step 5: Fix @parse. references in src/lambda/language.mbt**

`language.mbt` currently calls `@parse.parse_cst_recover_with_tokens` and
`@parse.syntax_node_to_ast_node`. After the move these are unqualified (same package):

```bash
grep -n "@parse\." src/lambda/language.mbt
```

Change each `@parse.` occurrence to unqualified. Expected occurrences:
- `@parse.parse_cst_recover_with_tokens(` → `parse_cst_recover_with_tokens(`
- `@parse.syntax_node_to_ast_node(` → `syntax_node_to_ast_node(`

**Step 6: Verify moon check**

```bash
moon check
```

Expected: no errors. If `parse_lambda_root is not defined` appears in `lambda_spec.mbt`,
confirm `cst_parser.mbt` exists in `src/lambda/` (both files are in the same package).

**Step 7: Run tests**

```bash
moon test
```

Expected: same or higher pass count (parser tests now run from both src/parser/ and
src/lambda/), zero failures.

**Step 8: Commit**

```bash
git add src/lambda/moon.pkg src/lambda/lambda_spec.mbt src/lambda/cst_parser.mbt \
        src/lambda/cst_convert.mbt src/lambda/parser.mbt src/lambda/error_recovery.mbt
git commit -m "refactor(lambda): move parser files into lambda; rewrite adapter to use @core.parse_tokens_indexed"
```

---

## Task 3: Move src/parser/ test files to src/lambda/

**Files:** copy 8 test files from src/parser/ to src/lambda/ (verbatim — no changes needed
since they test unqualified symbols now available in src/lambda/).

**Step 1: Copy test files**

```bash
cp src/parser/parser_test.mbt                  src/lambda/parser_test.mbt
cp src/parser/parse_tree_test.mbt              src/lambda/parse_tree_test.mbt
cp src/parser/cst_tree_test.mbt                src/lambda/cst_tree_test.mbt
cp src/parser/error_recovery_test.mbt          src/lambda/error_recovery_test.mbt
cp src/parser/error_recovery_phase3_test.mbt   src/lambda/error_recovery_phase3_test.mbt
cp src/parser/regression_test.mbt              src/lambda/regression_test.mbt
cp src/parser/parser_properties_test.mbt       src/lambda/parser_properties_test.mbt
cp src/parser/cst_parser_wbtest.mbt            src/lambda/cst_parser_wbtest.mbt
```

**Step 2: Verify and run tests**

```bash
moon check
moon test
```

Expected: pass count increases (both sets of parser tests run). Zero failures.

**Step 3: Commit**

```bash
git add src/lambda/
git commit -m "refactor(lambda): copy parser test files into lambda package"
```

---

## Task 4: Define ParseOutcome + IncrementalLanguage vtable in src/incremental/

No behavior changes. Just adds new types.

**Files:**
- Create: `src/incremental/incremental_language.mbt`

**Step 1: Create the file**

```moonbit
///|
/// Outcome of a parse attempt by IncrementalLanguage.
/// Tree carries the new syntax tree and the node reuse count (0 for full parses).
/// LexError carries the error message for on_lex_error dispatch.
pub enum ParseOutcome {
  Tree(@seam.SyntaxNode, Int)
  LexError(String)
}

///|
/// Token-erased vtable for incremental language integration.
///
/// Analogous to `@pipeline.Language[@Ast]`: the token type is erased into
/// closures at call site, keeping `IncrementalParser[@Ast]` generic.
///
/// `full_parse` — initial (non-incremental) parse. Returns Tree(syntax, 0)
///   or LexError(msg). The closure captures and manages TokenBuffer state.
///
/// `incremental_parse` — edit-triggered reparse. Receives the old SyntaxNode
///   so the closure can call SyntaxNode::cst_node() for the reuse cursor.
///   Returns Tree(new_syntax, reuse_count) or LexError(msg). The closure
///   captures and updates TokenBuffer and last_diagnostics state.
///
/// `to_ast` — convert a syntax tree to @Ast.
///
/// `on_lex_error` — build an error @Ast from a lex-error message.
pub struct IncrementalLanguage[@Ast] {
  priv full_parse : (String, @seam.Interner, @seam.NodeInterner) -> ParseOutcome
  priv incremental_parse : (String, @seam.SyntaxNode, @core.Edit, @seam.Interner, @seam.NodeInterner) -> ParseOutcome
  priv to_ast : (@seam.SyntaxNode) -> @Ast
  priv on_lex_error : (String) -> @Ast
}

///|
/// Constructor for IncrementalLanguage vtable.
pub fn[Ast] IncrementalLanguage::new(
  full_parse~ : (String, @seam.Interner, @seam.NodeInterner) -> ParseOutcome,
  incremental_parse~ : (String, @seam.SyntaxNode, @core.Edit, @seam.Interner, @seam.NodeInterner) -> ParseOutcome,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
) -> IncrementalLanguage[Ast] {
  { full_parse, incremental_parse, to_ast, on_lex_error }
}
```

**Step 2: Verify and run tests**

```bash
moon check && moon test
```

Expected: same count, zero failures.

**Step 3: Commit**

```bash
git add src/incremental/incremental_language.mbt
git commit -m "feat(incremental): add IncrementalLanguage vtable + ParseOutcome"
```

---

## Task 5: Add lambda_incremental_language() + LambdaIncrementalParser in src/lambda/

**Files:**
- Modify: `src/lambda/moon.pkg` (add @incremental)
- Create: `src/lambda/incremental.mbt`

**Step 1: Add @incremental to src/lambda/moon.pkg**

```
import {
  "dowdiness/parser/pipeline" @pipeline,
  "dowdiness/parser/lexer",
  "dowdiness/parser/ast",
  "dowdiness/parser/viz" @viz,
  "dowdiness/parser/token",
  "dowdiness/parser/syntax",
  "dowdiness/parser/core" @core,
  "dowdiness/seam" @seam,
  "moonbitlang/core/strconv",
  "dowdiness/parser/incremental" @incremental,
}

import {
  "moonbitlang/core/quickcheck",
} for "test"
```

**Step 2: Create src/lambda/incremental.mbt**

```moonbit
///|
/// Build an IncrementalLanguage[@ast.AstNode] for lambda calculus.
///
/// Token buffer and diagnostics state are captured as Refs inside closures,
/// keeping IncrementalParser[@ast.AstNode] language-agnostic.
pub fn lambda_incremental_language() -> @incremental.IncrementalLanguage[
  @ast.AstNode,
] {
  let token_buf : Ref[@core.TokenBuffer[@token.Token]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[@token.Token]]] = Ref::new([])
  @incremental.IncrementalLanguage::new(
    full_parse=fn(source, interner, node_interner) {
      try {
        let buffer = @core.TokenBuffer::new(
          source,
          tokenize_fn=@lexer.tokenize,
          eof_token=@token.EOF,
        )
        token_buf.val = Some(buffer)
        let (cst, diagnostics) = parse_cst_recover(
          source,
          interner=Some(interner),
          node_interner=Some(node_interner),
        )
        last_diags.val = diagnostics
        let syntax = @seam.SyntaxNode::from_cst(cst)
        @incremental.ParseOutcome::Tree(syntax, 0)
      } catch {
        @core.LexError(msg) => {
          token_buf.val = None
          last_diags.val = []
          @incremental.ParseOutcome::LexError("Tokenization error: " + msg)
        }
      }
    },
    incremental_parse=fn(source, old_syntax, edit, interner, node_interner) {
      // Step 1: Update token buffer incrementally
      let tokens = match token_buf.val {
        Some(buffer) =>
          try {
            buffer.update(edit, source)
          } catch {
            @core.LexError(msg) => {
              token_buf.val = None
              last_diags.val = []
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
            }
          }
        None =>
          try {
            let buffer = @core.TokenBuffer::new(
              source,
              tokenize_fn=@lexer.tokenize,
              eof_token=@token.EOF,
            )
            token_buf.val = Some(buffer)
            match token_buf.val {
              Some(b) => b.get_tokens()
              None => []
            }
          } catch {
            @core.LexError(msg) => {
              last_diags.val = []
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
            }
          }
      }
      // Step 2: Build reuse cursor from old CST and damaged range
      let damaged_range = @core.Range::new(edit.start, edit.new_end())
      let cursor = Some(
        make_reuse_cursor(
          old_syntax.cst_node(),
          damaged_range.start,
          damaged_range.end,
          tokens,
        ),
      )
      // Step 3: Incremental parse via @core
      let (new_cst, diagnostics, reuse_count) = parse_cst_recover_with_tokens(
        source,
        tokens,
        cursor,
        prev_diagnostics=Some(last_diags.val),
        interner=Some(interner),
        node_interner=Some(node_interner),
      )
      last_diags.val = diagnostics
      let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
      @incremental.ParseOutcome::Tree(new_syntax, reuse_count)
    },
    to_ast=fn(syntax) { syntax_node_to_ast_node(syntax, Ref::new(0)) },
    on_lex_error=fn(msg) { @ast.AstNode::error(msg, 0, 0) },
  )
}

///|
/// Lambda calculus incremental parser.
/// Wraps IncrementalParser[@ast.AstNode] with the lambda vtable pre-wired.
pub struct LambdaIncrementalParser {
  priv parser : @incremental.IncrementalParser[@ast.AstNode]
}

///|
pub fn LambdaIncrementalParser::new(source : String) -> LambdaIncrementalParser {
  {
    parser: @incremental.IncrementalParser::new(
      source,
      lambda_incremental_language(),
    ),
  }
}

///|
pub fn LambdaIncrementalParser::parse(
  self : LambdaIncrementalParser,
) -> @ast.AstNode {
  self.parser.parse()
}

///|
pub fn LambdaIncrementalParser::edit(
  self : LambdaIncrementalParser,
  edit : @core.Edit,
  new_source : String,
) -> @ast.AstNode {
  self.parser.edit(edit, new_source)
}

///|
pub fn LambdaIncrementalParser::get_tree(
  self : LambdaIncrementalParser,
) -> @ast.AstNode? {
  self.parser.get_tree()
}

///|
pub fn LambdaIncrementalParser::get_source(
  self : LambdaIncrementalParser,
) -> String {
  self.parser.get_source()
}

///|
pub fn LambdaIncrementalParser::stats(
  self : LambdaIncrementalParser,
) -> String {
  self.parser.stats()
}

///|
pub fn LambdaIncrementalParser::get_last_reuse_count(
  self : LambdaIncrementalParser,
) -> Int {
  self.parser.get_last_reuse_count()
}

///|
pub fn LambdaIncrementalParser::interner_size(
  self : LambdaIncrementalParser,
) -> Int {
  self.parser.interner_size()
}

///|
pub fn LambdaIncrementalParser::node_interner_size(
  self : LambdaIncrementalParser,
) -> Int {
  self.parser.node_interner_size()
}

///|
pub fn LambdaIncrementalParser::interner_clear(
  self : LambdaIncrementalParser,
) -> Unit {
  self.parser.interner_clear()
}
```

**Step 3: Verify moon check and tests**

```bash
moon check && moon test
```

Expected: all passing. If `old_syntax.cst_node()` is not accessible, check:
```bash
grep -rn "pub fn.*cst_node" seam/
```
If the method is not public, find the public accessor for `CstNode` from a `SyntaxNode` and use that instead.

**Step 4: Commit**

```bash
git add src/lambda/moon.pkg src/lambda/incremental.mbt \
        src/incremental/incremental_language.mbt
git commit -m "feat(lambda): add lambda_incremental_language vtable + LambdaIncrementalParser"
```

---

## Task 6: Move lambda-specific tests from src/incremental/ to src/lambda/

These test files use `IncrementalParser::new` / `@parse.parse_tree` — they test lambda
behavior and must move to `src/lambda/` where `LambdaIncrementalParser` lives. Moving them
now, before the IncrementalParser generification in Task 7, means tests stay green throughout.

**Files to move (lambda-specific):**
- `incremental_parser_test.mbt`
- `incremental_differential_fuzz_test.mbt`
- `interner_integration_test.mbt`
- `node_interner_integration_test.mbt`
- `phase4_correctness_test.mbt`

**Files to keep in src/incremental/ (generic):**
- `damage_test.mbt` — tests DamageTracker only
- `perf_instrumentation.mbt` — production code

**Step 1: Copy test files**

```bash
cp src/incremental/incremental_parser_test.mbt            src/lambda/incremental_parser_test.mbt
cp src/incremental/incremental_differential_fuzz_test.mbt src/lambda/incremental_differential_fuzz_test.mbt
cp src/incremental/interner_integration_test.mbt          src/lambda/interner_integration_test.mbt
cp src/incremental/node_interner_integration_test.mbt     src/lambda/node_interner_integration_test.mbt
cp src/incremental/phase4_correctness_test.mbt            src/lambda/phase4_correctness_test.mbt
```

**Step 2: Update all copied test files**

In every copied test file apply these substitutions:
- `IncrementalParser::new(` → `LambdaIncrementalParser::new(`
- `@incremental.IncrementalParser::new(` → `LambdaIncrementalParser::new(`
- Any `@parse.parse_tree(` → `parse_tree(` (unqualified — same package)
- Any other `@parse.` prefix → remove (parser functions are now in src/lambda/)

Check after each file:
```bash
moon check -p dowdiness/parser/lambda
```

**Step 3: Delete old copies from src/incremental/**

```bash
rm src/incremental/incremental_parser_test.mbt
rm src/incremental/incremental_differential_fuzz_test.mbt
rm src/incremental/interner_integration_test.mbt
rm src/incremental/node_interner_integration_test.mbt
rm src/incremental/phase4_correctness_test.mbt
```

**Step 4: Verify**

```bash
moon check && moon test
```

Expected: same or higher pass count, zero failures.

**Step 5: Commit**

```bash
git add src/lambda/ src/incremental/
git commit -m "refactor(incremental): move lambda-specific tests to lambda package"
```

---

## Task 7: Generify IncrementalParser using the vtable

**Files:**
- Modify: `src/incremental/incremental_parser.mbt`
- Modify: `src/incremental/moon.pkg`

**Step 1: Replace src/incremental/moon.pkg**

```text
import {
  "dowdiness/parser/core" @core,
  "dowdiness/seam" @seam,
}
```

**Step 2: Replace src/incremental/incremental_parser.mbt**

```moonbit
// Generic incremental parser — Wagner-Graham damage tracking strategy.
// Language-specific behavior injected via IncrementalLanguage[@Ast] vtable.

///|
pub struct IncrementalParser[@Ast] {
  priv lang : IncrementalLanguage[@Ast]
  mut source : String
  mut tree : @Ast?
  mut syntax_tree : @seam.SyntaxNode?
  mut last_reuse_count : Int
  priv interner : @seam.Interner
  priv node_interner : @seam.NodeInterner
}

///|
pub fn[Ast] IncrementalParser::new(
  source : String,
  lang : IncrementalLanguage[Ast],
) -> IncrementalParser[Ast] {
  {
    lang,
    source,
    tree: None,
    syntax_tree: None,
    last_reuse_count: 0,
    interner: @seam.Interner::new(),
    node_interner: @seam.NodeInterner::new(),
  }
}

///|
pub fn[Ast] IncrementalParser::interner_size(self : IncrementalParser[Ast]) -> Int {
  self.interner.size()
}

///|
pub fn[Ast] IncrementalParser::node_interner_size(
  self : IncrementalParser[Ast],
) -> Int {
  self.node_interner.size()
}

///|
pub fn[Ast] IncrementalParser::interner_clear(
  self : IncrementalParser[Ast],
) -> Unit {
  self.interner.clear()
  self.node_interner.clear()
}

///|
pub fn[Ast] IncrementalParser::parse(self : IncrementalParser[Ast]) -> Ast {
  let tree = match (self.lang.full_parse)(
    self.source,
    self.interner,
    self.node_interner,
  ) {
    Tree(syntax, _) => {
      self.syntax_tree = Some(syntax)
      self.last_reuse_count = 0
      (self.lang.to_ast)(syntax)
    }
    LexError(msg) => {
      self.syntax_tree = None
      self.last_reuse_count = 0
      (self.lang.on_lex_error)(msg)
    }
  }
  self.tree = Some(tree)
  tree
}

///|
pub fn[Ast] IncrementalParser::edit(
  self : IncrementalParser[Ast],
  edit : @core.Edit,
  new_source : String,
) -> Ast {
  self.source = new_source
  if self.syntax_tree is None {
    return self.parse()
  }
  let new_tree = match self.syntax_tree {
    Some(old_syntax) =>
      match (self.lang.incremental_parse)(
        new_source,
        old_syntax,
        edit,
        self.interner,
        self.node_interner,
      ) {
        Tree(new_syntax, reuse_count) => {
          self.syntax_tree = Some(new_syntax)
          self.last_reuse_count = reuse_count
          (self.lang.to_ast)(new_syntax)
        }
        LexError(msg) => {
          self.syntax_tree = None
          self.last_reuse_count = 0
          (self.lang.on_lex_error)(msg)
        }
      }
    None => self.parse()
  }
  self.tree = Some(new_tree)
  new_tree
}

///|
pub fn[Ast] IncrementalParser::get_tree(self : IncrementalParser[Ast]) -> Ast? {
  self.tree
}

///|
pub fn[Ast] IncrementalParser::get_source(
  self : IncrementalParser[Ast],
) -> String {
  self.source
}

///|
pub fn[Ast] IncrementalParser::stats(self : IncrementalParser[Ast]) -> String {
  "IncrementalParser { source_length: " +
  self.source.length().to_string() +
  " }"
}

///|
pub fn[Ast] IncrementalParser::get_last_reuse_count(
  self : IncrementalParser[Ast],
) -> Int {
  self.last_reuse_count
}
```

**Step 3: Verify moon check and tests**

```bash
moon check && moon test
```

Expected: same pass count, zero failures. Lambda tests are in src/lambda/ using
LambdaIncrementalParser, so they're unaffected by the generic refactor.

**Step 4: Commit**

```bash
git add src/incremental/incremental_parser.mbt src/incremental/moon.pkg
git commit -m "refactor(incremental): generify IncrementalParser[@Ast] with IncrementalLanguage vtable"
```

---

## Task 8: Update src/benchmarks/

**Files:**
- Modify: `src/benchmarks/moon.pkg`
- Modify: `src/benchmarks/benchmark.mbt` (and any other benchmark files using @parse)

**Step 1: Update src/benchmarks/moon.pkg**

Remove `"dowdiness/parser/parser" @parse`:

```text
import {
  "dowdiness/parser/core" @core,
  "dowdiness/parser/lexer",
  "dowdiness/parser/lambda" @lambda,
  "dowdiness/parser/incremental",
  "dowdiness/parser/token",
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
}
```

**Step 2: Update all benchmark files**

Four files need updates: `benchmark.mbt`, `performance_benchmark.mbt`, `heavy_benchmark.mbt`,
`cst_benchmark.mbt`. Apply these substitutions across all of them:

- `@parse.parse_tree(` → `@lambda.parse_tree(`
- `@parse.parse_with_error_recovery(` → `@lambda.parse_with_error_recovery(`
- `@parse.parse_cst_recover(` → `@lambda.parse_cst_recover(`
- `@parse.make_reuse_cursor(` → `@lambda.make_reuse_cursor(`
- `@parse.parse_cst_recover_with_tokens(` → `@lambda.parse_cst_recover_with_tokens(`
- `@parse.parse_cst_with_cursor(` → `@lambda.parse_cst_with_cursor(`
- `@incremental.IncrementalParser::new(` → `@lambda.LambdaIncrementalParser::new(`

Note: `@incremental.DamageTracker::new(` in `benchmark.mbt` stays — `DamageTracker` remains
in `src/incremental/` (not lambda-specific). `@token.EOF` in `performance_benchmark.mbt`
stays — `@token` is still imported.

Verify no @parse references remain:
```bash
grep -rn "@parse\." src/benchmarks/
```

**Step 3: Verify**

```bash
moon check && moon test
moon bench --release -p dowdiness/parser/benchmarks
```

Expected: all passing, benchmarks run without error.

**Step 4: Commit**

```bash
git add src/benchmarks/
git commit -m "refactor(benchmarks): migrate from @parse to @lambda, use LambdaIncrementalParser"
```

---

## Task 9: Delete src/parser/ package

**Step 1: Verify no remaining imports**

```bash
grep -rn '"dowdiness/parser/parser"' src/ --include="*.pkg"
```

Expected: zero results.

**Step 2: Delete the package**

```bash
rm -rf src/parser/
```

**Step 3: Verify**

```bash
moon check && moon test
```

Expected: same pass count, zero failures.

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete src/parser/ (grammar + adapter consolidated into src/lambda/ + @core)"
```

---

## Task 10: Update interfaces, format, docs, final verification

**Step 1: Update interfaces**

```bash
moon info
git diff *.mbti
```

Expected changes:
- `src/lambda/*.mbti` gains symbols formerly in `src/parser/*.mbti`
- `src/incremental/*.mbti` loses lambda-specific symbols, gains generic type params
- `src/core/*.mbti` gains `parse_tokens_indexed` + `LanguageSpec::parse_root`
- `src/parser/*.mbti` — deleted files, ignore

**Step 2: Format**

```bash
moon fmt
```

**Step 3: Full test suite**

```bash
moon test
```

Expected: all passing.

**Step 4: Archive old plans and update docs/README.md**

```bash
# The v2 plan was already deleted. The abandoned v1 plan was deleted earlier.
# Nothing to archive.
```

Update `docs/README.md` — move the v3 plan entry from Active Plans to Archive:
- Remove: `plans/2026-02-28-consolidate-lambda-v3.md`
- Add to Archive: `archive/completed-phases/2026-02-28-consolidate-lambda-v3.md`

Then `git mv` the plan file:
```bash
git mv docs/plans/2026-02-28-consolidate-lambda-v3.md \
       docs/archive/completed-phases/2026-02-28-consolidate-lambda-v3.md
```

Add `**Status:** Complete` near the top of the archived file.

**Step 5: Validate docs**

```bash
bash check-docs.sh
```

Expected: no warnings.

**Step 6: Commit**

```bash
git add -A
git commit -m "chore: update interfaces, format, archive plan, update docs index"
```

---

## Quick Verification Checklist

After all tasks complete:

```bash
# No references to @parse anywhere
grep -rn '"dowdiness/parser/parser"' src/ --include="*.pkg"
# → zero results

# No lambda-specific types in incremental
grep -n "@token\|@ast\|@lexer\|@parse" src/incremental/moon.pkg
# → zero results

# @core has parse_tokens_indexed and LanguageSpec::parse_root
grep -n "parse_tokens_indexed\|parse_root" src/core/lib.mbt
# → both present

# All tests pass
moon test
# → zero failures

# Docs clean
bash check-docs.sh
# → no warnings
```
