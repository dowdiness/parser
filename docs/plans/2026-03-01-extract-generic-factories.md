# Grammar Abstraction — Zero Public Vtables

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Introduce `Grammar[T, K, Ast]` as the single grammar description type, with bridge factories that produce `IncrementalParser[Ast]` and `ParserDb[Ast]` directly — hiding vtable construction from grammar authors entirely.

**Architecture:** A new `src/bridge/` package defines `Grammar[T, K, Ast]` (3 fields: spec, tokenize, to_ast) and two factory functions that erase `T`/`K` internally via struct-of-closures. `IncrementalLanguage[Ast]` and `Language[Ast]` become implementation details — still used internally for type erasure, never constructed by grammar authors. `@pipeline` stays independent of `@core`. Lex error handling is derived automatically: the factory parses 0 tokens to produce an error CST and runs `to_ast` on it — grammar authors never write `on_lex_error`.

**Tech Stack:** MoonBit, `moon check`, `moon test`, `moon bench --release`

---

## Design

### The problem

A grammar provides three things: `spec`, `tokenize`, `to_ast`. Everything else — TokenBuffer lifecycle, ReuseCursor construction, diagnostic formatting, interner threading, lex error handling — is infrastructure wiring identical across all grammars. Currently the grammar author must construct two different vtable types (`IncrementalLanguage[Ast]` for incremental, `Language[Ast]` for reactive), provide a redundant `on_lex_error` callback, and write wrapper structs around the consumers. This is ~200 lines of boilerplate that leaks execution-model details.

### The solution

```
Grammar[T, K, Ast]              ← grammar defines once (3 fields)
       │
       ├──→ new_incremental_parser(source, grammar) → IncrementalParser[Ast]
       └──→ new_parser_db(source, grammar)           → ParserDb[Ast]
```

Grammar authors never see `IncrementalLanguage` or `Language`. The factories create fresh state per parser (eliminating the IncrementalLanguage sharing footgun).

### Dependency graph

```
@core ──→ @seam
@incremental ──→ @core, @seam
@pipeline ──→ @seam, @incr

@bridge ──→ @core, @incremental, @pipeline, @seam   (leaf — nothing depends on it)
```

`@pipeline` stays independent of `@core`. The bridge is the only package that knows all layers.

### Lambda before/after

**Before (~240 lines):**
- `lambda_incremental_language()` — 90 lines of TokenBuffer/ReuseCursor/closure wiring
- `LambdaIncrementalParser` — 75 lines of delegation (9 methods)
- `LambdaLanguage` + `Parseable` impl — 25 lines
- `LambdaParserDb` — 30 lines of delegation (5 methods)
- `lambda_language()` — 10 lines
- `make_reuse_cursor` — 10 lines

**After (~8 lines):**
```moonbit
pub let lambda_grammar : @bridge.Grammar[@token.Token, @syntax.SyntaxKind, @ast.AstNode] = @bridge.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  to_ast=fn(s) { syntax_node_to_ast_node(s, Ref::new(0)) },
)
```

### Escape hatch

Grammars with non-standard needs (custom TokenBuffer management, unusual damage tracking) bypass `Grammar` and construct `IncrementalLanguage::new()` or `Language::from()` directly.

---

### Task 1: Create `src/bridge/` package

**Files:**
- Create: `src/bridge/moon.pkg`
- Create: `src/bridge/grammar.mbt`
- Create: `src/bridge/factories.mbt`

**Step 1: Create `src/bridge/moon.pkg`**

```json
import {
  "dowdiness/parser/core" @core,
  "dowdiness/parser/incremental" @incremental,
  "dowdiness/parser/pipeline" @pipeline,
  "dowdiness/seam" @seam,
}
```

**Step 2: Create `src/bridge/grammar.mbt`**

```moonbit
///|
/// Complete grammar description — the three things that vary per language.
///
/// Everything else (TokenBuffer lifecycle, ReuseCursor construction,
/// diagnostic formatting, lex error handling) is derived by the factories.
///
/// Define one per grammar as a module-level `let` and pass it to
/// `new_incremental_parser` or `new_parser_db`.
pub struct Grammar[T, K, Ast] {
  spec : @core.LanguageSpec[T, K]
  tokenize : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError
  to_ast : (@seam.SyntaxNode) -> Ast
}

///|
pub fn[T, K, Ast] Grammar::new(
  spec~ : @core.LanguageSpec[T, K],
  tokenize~ : (String) -> Array[@core.TokenInfo[T]] raise @core.LexError,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
) -> Grammar[T, K, Ast] {
  { spec, tokenize, to_ast }
}
```

**Step 3: Create `src/bridge/factories.mbt`**

```moonbit
// Bridge factories — build IncrementalParser or ParserDb from a Grammar.
//
// These encapsulate all infrastructure wiring: TokenBuffer lifecycle,
// ReuseCursor construction, parse_tokens_indexed calls, diagnostic
// formatting, lex error handling. The grammar author provides only what
// varies (spec, tokenize, to_ast); the factories handle the rest.
//
// Lex error strategy: parse 0 tokens → error CST → to_ast produces the
// error AST. The lex error message goes into diagnostics, not the AST.
//
// IncrementalLanguage[Ast] and Language[Ast] are constructed internally
// for type erasure — grammar authors never see them.

///|
/// Parse 0 tokens to produce an error CST, then run to_ast.
/// Derives on_lex_error from the grammar's existing to_ast callback.
fn[T, K, Ast] derive_lex_error_ast(
  grammar : Grammar[T, K, Ast],
) -> Ast {
  let spec = grammar.spec
  let (cst, _, _) = @core.parse_tokens_indexed(
    "",
    0,
    fn(_) { spec.eof_token },
    fn(_) { 0 },
    fn(_) { 0 },
    spec,
  )
  (grammar.to_ast)(@seam.SyntaxNode::from_cst(cst))
}

///|
/// Create an IncrementalParser from a Grammar.
///
/// Each call creates fresh internal state (TokenBuffer, diagnostics).
/// Safe to call multiple times — no shared mutable state between parsers.
pub fn[T, K, Ast] new_incremental_parser(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @incremental.IncrementalParser[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let to_ast = grammar.to_ast
  let token_buf : Ref[@core.TokenBuffer[T]?] = Ref::new(None)
  let last_diags : Ref[Array[@core.Diagnostic[T]]] = Ref::new([])
  let lang = @incremental.IncrementalLanguage::new(
    full_parse=(source, interner, node_interner) => {
      try {
        let buffer = @core.TokenBuffer::new(
          source,
          tokenize_fn=tokenize,
          eof_token=spec.eof_token,
        )
        token_buf.val = Some(buffer)
        let tokens = buffer.get_tokens()
        let (cst, diagnostics, _) = @core.parse_tokens_indexed(
          source,
          tokens.length(),
          fn(i) { tokens[i].token },
          fn(i) { tokens[i].start },
          fn(i) { tokens[i].end },
          spec,
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
    incremental_parse=(source, old_syntax, edit, interner, node_interner) => {
      let tokens = match token_buf.val {
        Some(buffer) =>
          buffer.update(edit, source) catch {
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
              tokenize_fn=tokenize,
              eof_token=spec.eof_token,
            )
            token_buf.val = Some(buffer)
            buffer.get_tokens()
          } catch {
            @core.LexError(msg) => {
              last_diags.val = []
              return @incremental.ParseOutcome::LexError(
                "Tokenization error: " + msg,
              )
            }
          }
      }
      let damaged_range = @core.Range::new(edit.start, edit.new_end())
      let cursor = Some(
        @core.ReuseCursor::new(
          old_syntax.cst_node(),
          damaged_range.start,
          damaged_range.end,
          tokens.length(),
          fn(i) { tokens[i].token },
          fn(i) { tokens[i].start },
          spec,
        ),
      )
      let (new_cst, diagnostics, reuse_count) = @core.parse_tokens_indexed(
        source,
        tokens.length(),
        fn(i) { tokens[i].token },
        fn(i) { tokens[i].start },
        fn(i) { tokens[i].end },
        spec,
        cursor~,
        prev_diagnostics=Some(last_diags.val),
        interner=Some(interner),
        node_interner=Some(node_interner),
      )
      last_diags.val = diagnostics
      let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
      @incremental.ParseOutcome::Tree(new_syntax, reuse_count)
    },
    to_ast=fn(syntax) { to_ast(syntax) },
    on_lex_error=fn(_msg) { derive_lex_error_ast(grammar) },
  )
  @incremental.IncrementalParser::new(source, lang)
}

///|
/// Create a ParserDb from a Grammar.
pub fn[T, K, Ast : Eq] new_parser_db(
  source : String,
  grammar : Grammar[T, K, Ast],
) -> @pipeline.ParserDb[Ast] {
  let spec = grammar.spec
  let tokenize = grammar.tokenize
  let to_ast = grammar.to_ast
  let lang : @pipeline.Language[Ast] = @pipeline.Language::from_closures(
    parse_source=fn(s) {
      try tokenize(s) catch {
        @core.LexError(msg) => {
          let (cst, _, _) = @core.parse_tokens_indexed(
            "",
            0,
            fn(_) { spec.eof_token },
            fn(_) { 0 },
            fn(_) { 0 },
            spec,
          )
          @pipeline.CstStage::{
            cst,
            diagnostics: ["tokenization: " + msg],
            is_lex_error: true,
          }
        }
      } noraise {
        tokens => {
          let (cst, diags, _) = @core.parse_tokens_indexed(
            s,
            tokens.length(),
            fn(i) { tokens[i].token },
            fn(i) { tokens[i].start },
            fn(i) { tokens[i].end },
            spec,
          )
          @pipeline.CstStage::{
            cst,
            diagnostics: diags.map(fn(d) {
              d.message +
              " [" +
              d.start.to_string() +
              "," +
              d.end.to_string() +
              "]"
            }),
            is_lex_error: false,
          }
        }
      }
    },
    to_ast=fn(n) { to_ast(n) },
    on_lex_error=fn(_msg) { derive_lex_error_ast(grammar) },
  )
  @pipeline.ParserDb::new(source, lang)
}
```

**Step 4: Add `Language::from_closures` to `@pipeline`**

The `new_parser_db` factory above needs a way to construct `Language[Ast]` from raw closures without going through a `Parseable` struct. Add to `src/pipeline/language.mbt`:

```moonbit
///|
/// Construct a Language directly from closures.
/// Use this when you don't need the Parseable trait pattern.
pub fn[Ast] Language::from_closures(
  parse_source~ : (String) -> CstStage,
  to_ast~ : (@seam.SyntaxNode) -> Ast,
  on_lex_error~ : (String) -> Ast,
) -> Language[Ast] {
  { parse_source, to_ast, on_lex_error }
}
```

**Step 5: Run check**

Run: `moon check`
Expected: no errors

**Step 6: Commit**

```bash
git add src/bridge/ src/pipeline/language.mbt
git commit -m "feat: add Grammar[T,K,Ast] + bridge factories"
```

---

### Task 2: Add `lambda_grammar` and update `src/lib.mbt`

**Files:**
- Create: `src/examples/lambda/grammar.mbt`
- Modify: `src/examples/lambda/moon.pkg` — add `@bridge` import
- Modify: `src/lib.mbt` — use bridge factories
- Modify: `src/moon.pkg` — add `@bridge` import

**Step 1: Create `src/examples/lambda/grammar.mbt`**

```moonbit
///|
/// Lambda calculus grammar description.
///
/// This is the complete integration surface — a single value that
/// bridge factories consume to produce IncrementalParser or ParserDb.
pub let lambda_grammar : @bridge.Grammar[
  @token.Token,
  @syntax.SyntaxKind,
  @ast.AstNode,
] = @bridge.Grammar::new(
  spec=lambda_spec,
  tokenize=@lexer.tokenize,
  to_ast=fn(s) { syntax_node_to_ast_node(s, Ref::new(0)) },
)
```

**Step 2: Add `@bridge` to `src/examples/lambda/moon.pkg`**

Add `"dowdiness/parser/bridge" @bridge,` to the imports.

**Step 3: Update `src/lib.mbt`**

Change `incremental()` to use the bridge factory:

```moonbit
pub fn incremental(source : String) -> @incremental.IncrementalParser[@ast.AstNode] {
  @bridge.new_incremental_parser(source, @lambda.lambda_grammar)
}
```

Add `@bridge` import to `src/moon.pkg` and `@incremental` if not present.

**Step 4: Run tests**

Run: `moon test`
Expected: all pass (additive change, nothing removed yet)

**Step 5: Commit**

```bash
git add src/examples/lambda/grammar.mbt src/examples/lambda/moon.pkg \
  src/lib.mbt src/moon.pkg
git commit -m "feat(lambda): add lambda_grammar, update facade to use bridge"
```

---

### Task 3: Delete `LambdaIncrementalParser` + migrate callers

**Files:**
- Modify: `src/examples/lambda/incremental.mbt` — delete `LambdaIncrementalParser` struct + all 9 methods (lines 105–180)
- Modify: `src/examples/lambda/incremental_parser_test.mbt` — replace all `LambdaIncrementalParser::new(s)` with `@bridge.new_incremental_parser(s, lambda_grammar)`
- Modify: `src/examples/lambda/interner_integration_test.mbt` — same
- Modify: `src/examples/lambda/node_interner_integration_test.mbt` — same
- Modify: `src/examples/lambda/incremental_differential_fuzz_test.mbt` — same (3 occurrences)
- Modify: `src/benchmarks/benchmark.mbt` — replace `@lambda.LambdaIncrementalParser::new(s)` with `@bridge.new_incremental_parser(s, @lambda.lambda_grammar)`
- Modify: `src/benchmarks/performance_benchmark.mbt` — same
- Modify: `src/benchmarks/heavy_benchmark.mbt` — same
- Modify: `src/benchmarks/moon.pkg` — add `@bridge` import

**Step 1: Delete `LambdaIncrementalParser` from `incremental.mbt`**

Remove the struct definition and all 9 methods (lines 105–180).

**Step 2: Update whitebox tests**

In `incremental_parser_test.mbt`, `interner_integration_test.mbt`, `node_interner_integration_test.mbt`, `incremental_differential_fuzz_test.mbt`:

Replace every `LambdaIncrementalParser::new(` with `@bridge.new_incremental_parser(` and append `, lambda_grammar)` as the second argument.

**Step 3: Update benchmarks**

In `src/benchmarks/benchmark.mbt`, `performance_benchmark.mbt`, `heavy_benchmark.mbt`:

Replace every `@lambda.LambdaIncrementalParser::new(` with `@bridge.new_incremental_parser(` and append `, @lambda.lambda_grammar)` as the second argument.

Add `"dowdiness/parser/bridge" @bridge,` to `src/benchmarks/moon.pkg`.

**Step 4: Run tests**

Run: `moon test`
Expected: all pass

**Step 5: Run `moon info && moon fmt`**

**Step 6: Commit**

```bash
git add src/examples/lambda/incremental.mbt \
  src/examples/lambda/incremental_parser_test.mbt \
  src/examples/lambda/interner_integration_test.mbt \
  src/examples/lambda/node_interner_integration_test.mbt \
  src/examples/lambda/incremental_differential_fuzz_test.mbt \
  src/benchmarks/benchmark.mbt src/benchmarks/performance_benchmark.mbt \
  src/benchmarks/heavy_benchmark.mbt src/benchmarks/moon.pkg \
  src/examples/lambda/pkg.generated.mbti
git commit -m "refactor: delete LambdaIncrementalParser, use bridge factory"
```

---

### Task 4: Delete `LambdaParserDb` + `LambdaLanguage` + migrate callers

**Files:**
- Modify: `src/examples/lambda/language.mbt` — delete `LambdaLanguage` struct, `Parseable` impl, `lambda_language()`, `LambdaParserDb` struct + all 5 methods (entire file becomes empty or deleted)
- Modify: `src/examples/lambda/lambda_parser_db_test.mbt` — replace `@lambda.LambdaParserDb` with `@bridge.new_parser_db` + `@pipeline.ParserDb`
- Modify: `src/benchmarks/parserdb_benchmark.mbt` — same

**Step 1: Delete `language.mbt` contents**

Delete `LambdaLanguage`, its `Parseable` impl, `lambda_language()`, and `LambdaParserDb` with all methods. The file can be deleted entirely.

**Step 2: Update `lambda_parser_db_test.mbt`**

Replace all occurrences:
- `@lambda.LambdaParserDb::new(s)` → `@bridge.new_parser_db(s, @lambda.lambda_grammar)`
- `@lambda.LambdaParserDb::term(db)` → `@pipeline.ParserDb::term(db)`
- `@lambda.LambdaParserDb::cst(db)` → `@pipeline.ParserDb::cst(db)`
- `@lambda.LambdaParserDb::diagnostics(db)` → `@pipeline.ParserDb::diagnostics(db)`
- `@lambda.LambdaParserDb::set_source(db, s)` → `@pipeline.ParserDb::set_source(db, s)`

Ensure the test file package imports include `@bridge` and `@pipeline`.

**Step 3: Update `src/benchmarks/parserdb_benchmark.mbt`**

Same replacements as Step 2. Verify `src/benchmarks/moon.pkg` has `@pipeline` import (add if needed).

**Step 4: Run tests**

Run: `moon test`
Expected: all pass

**Step 5: Run `moon info && moon fmt`**

**Step 6: Commit**

```bash
git add src/examples/lambda/language.mbt \
  src/examples/lambda/lambda_parser_db_test.mbt \
  src/benchmarks/parserdb_benchmark.mbt \
  src/examples/lambda/pkg.generated.mbti
git commit -m "refactor: delete LambdaParserDb/LambdaLanguage, use bridge factory"
```

---

### Task 5: Delete dead code

With factories handling all wiring internally, several lambda functions lose their only callers.

**Files:**
- Modify: `src/examples/lambda/incremental.mbt` — delete `lambda_incremental_language()`
- Modify: `src/examples/lambda/cst_parser.mbt` — delete `make_reuse_cursor`, `parse_cst_recover_with_tokens`, `parse_cst_with_cursor`
- Modify: `src/examples/lambda/cst_parser_wbtest.mbt` — delete tests for deleted functions

**Step 1: Grep for remaining callers**

Run: `grep -rn 'lambda_incremental_language\|parse_cst_recover_with_tokens\|parse_cst_with_cursor\|make_reuse_cursor\|lambda_language' src/ --include='*.mbt'`

Verify these functions are only called by code already deleted in Tasks 3–4 and by their own tests. If any production caller remains, keep that function.

`parse_cst_recover` and `parse_cst` should still have callers (`error_recovery.mbt`, `parser.mbt`, tests, benchmarks) — keep them.

**Step 2: Delete the functions**

In `incremental.mbt`: delete `lambda_incremental_language()`.

In `cst_parser.mbt`: delete `make_reuse_cursor`, `parse_cst_recover_with_tokens`, `parse_cst_with_cursor`.

In `cst_parser_wbtest.mbt`: delete tests `"parse_cst_recover_with_tokens: uses supplied tokens, not re-tokenization"` and `"parse_cst_with_cursor: uses supplied tokens, not re-tokenization"`.

**Step 3: Clean up unused imports in `src/examples/lambda/moon.pkg`**

Remove `@pipeline` and `@incremental` imports if no remaining code in the package references them. Run `moon check` to verify.

Note: keep `@pipeline` if `lambda_parser_db_test.mbt` (blackbox test) references `@pipeline.ParserDb`. Keep `@incremental` if `incremental_parser_test.mbt` references `@incremental.IncrementalParser`.

**Step 4: Run tests**

Run: `moon test`
Expected: all pass

**Step 5: Run `moon info && moon fmt`**

**Step 6: Commit**

```bash
git add src/examples/lambda/incremental.mbt \
  src/examples/lambda/cst_parser.mbt \
  src/examples/lambda/cst_parser_wbtest.mbt \
  src/examples/lambda/moon.pkg \
  src/examples/lambda/pkg.generated.mbti
git commit -m "refactor(lambda): delete dead vtable/wiring code"
```

---

### Task 6: Update docs

**Files:**
- Modify: `docs/architecture/polymorphism-patterns.md` — update struct-of-closures example to show Grammar as primary, manual construction as escape hatch
- Modify: `CLAUDE.md` — update package map (add `src/bridge/`, update `src/examples/lambda/`)
- Modify: `README.md` — update if it references deleted types
- Modify: `src/examples/lambda/README.md` — remove references to deleted types, document `lambda_grammar`
- Modify: `src/pipeline/README.md` — mention `Language::from_closures`
- Modify: `docs/api/pipeline-api-contract.md` — update worked example
- Modify: `docs/README.md` — move this plan to Archive section

**Step 1: Update `polymorphism-patterns.md`**

In section 3 (struct-of-closures), replace the `lambda_incremental_language()` example with:

```markdown
### Recommended: Grammar + bridge factory

```moonbit
// Grammar describes what varies (3 fields); bridge handles everything else.
pub let lambda_grammar = @bridge.Grammar::new(
  spec=lambda_spec, tokenize=@lexer.tokenize, to_ast=...,
)

// Caller chooses execution model:
let parser = @bridge.new_incremental_parser("λx.x", lambda_grammar)
let db = @bridge.new_parser_db("λx.x", lambda_grammar)
```

### Escape hatch: manual vtable construction

For grammars with non-standard requirements (custom TokenBuffer management,
unusual damage tracking), construct `IncrementalLanguage::new()` directly
with hand-written closures:

```moonbit
let lang = @incremental.IncrementalLanguage::new(
  full_parse=(source, interner, node_interner) => {
    // Custom tokenize + parse logic with Ref captures...
  },
  ...
)
let parser = @incremental.IncrementalParser::new(source, lang)
```
```

Update the "Where Each Pattern Appears" table at the bottom accordingly.

**Step 2: Update other docs**

- `CLAUDE.md`: Add `| src/bridge/ | Grammar[T,K,Ast], factory functions for IncrementalParser + ParserDb |` to package map
- `src/examples/lambda/README.md`: Replace `LambdaIncrementalParser`, `LambdaParserDb`, `LambdaLanguage` references with `lambda_grammar` + bridge factory usage
- `docs/README.md`: Add plan to Archive section when complete

**Step 3: Run `bash check-docs.sh`**

Expected: no warnings

**Step 4: Commit**

```bash
git add docs/ CLAUDE.md README.md src/examples/lambda/README.md \
  src/pipeline/README.md
git commit -m "docs: update for Grammar abstraction + bridge factories"
```

---

## Verification checklist

After all tasks:

- [ ] `moon check` — no errors
- [ ] `moon test` — all tests pass
- [ ] `moon info && moon fmt` — interfaces updated, code formatted
- [ ] `moon bench --release` — benchmarks compile and run
- [ ] `bash check-docs.sh` — no warnings
- [ ] No references to `LambdaIncrementalParser`, `LambdaParserDb`, `LambdaLanguage`, `lambda_incremental_language`, `lambda_language` remain in non-archive `.mbt` or `.md` files
- [ ] `Grammar` struct has exactly 3 fields: `spec`, `tokenize`, `to_ast` — no `on_lex_error`
- [ ] `grep -rn 'Grammar' src/bridge/` confirms Grammar struct + factories exist
- [ ] `grep -rn 'lambda_grammar' src/examples/lambda/` confirms single grammar definition
