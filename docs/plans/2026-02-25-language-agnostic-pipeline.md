# Language-Agnostic Pipeline — Partial Trait + Same-Name Struct

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status: ✅ COMPLETE** — Implemented 2026-02-26 (commits `6b0287a`, `cfdfea3`).

**Goal:** Separate lambda-calculus-specific code from the reactive pipeline infrastructure by introducing a `src/pipeline/` package. Language designers implement `trait Language` (partial contract) and get a full `Signal → Memo[CstStage] → Memo[Ast]` pipeline for free via `struct Language[Ast : Eq]` (same name, token-erased vtable) and `ParserDb[Ast : Eq]`.

**Architecture:**
```
src/pipeline/     ← NEW: language-agnostic reactive pipeline
  CstStage          moved from src/incremental/ (language-agnostic, gains lex_failed field)
  Language trait    parse_source(Self, String) -> CstStage
  Language[Ast]     same-name struct: token-erased vtable
  ParserDb[Ast]     Signal[String] → Memo[CstStage] → Memo[Ast]

src/lambda/       ← NEW: lambda calculus wiring
  LambdaLanguage    impl Language for LambdaLanguage
  LambdaParserDb    type alias + convenience constructor

src/incremental/  ← MODIFIED: CstStage definition removed; re-exported from pipeline/
```

**Key decisions:**
- `trait Language` has no type parameters (MoonBit constraint) — Token hidden inside `Self`
- `struct Language[Ast : Eq]` (same name) erases Token into closures
- `parse_source` returns `CstStage` directly — no tuple, no string-prefix error detection
- `CstStage` gains `lex_failed : Bool` for typed lex-error routing in `term_memo`
- Generic `ParserDb[Ast]` has two memos; existing lambda `ParserDb` (three memos) kept unchanged in `src/incremental/` for backward compatibility — only its `CstStage` definition is removed and re-exported from `pipeline/`

---

## Background for the implementer

**`trait Language`** — partial trait (no type params). Returns `CstStage` directly, fusing tokenization and parsing. Token is hidden inside `Self`.

**`struct Language[Ast : Eq]`** — same name as trait. Three closure fields. Token captured at construction time and erased from all downstream types.

**`Language::from[T : Language, Ast : Eq]`** — bridge from trait implementor to dictionary struct.

**`CstStage`** — moved from `src/incremental/incr_parser_db.mbt` to `src/pipeline/language.mbt`. Gains `lex_failed : Bool` field. `term_memo` uses this typed flag instead of string-prefix matching.

**`ParserDb[Ast : Eq]`** — `cst_memo` calls `lang.parse_source`; `term_memo` reads `cst_memo.get()` (registers dependency), checks `lex_failed`, calls `lang.to_ast` or `lang.on_lex_error`.

**`LambdaLanguage`** — fuses `@lexer.tokenize` + `@parse.parse_cst_recover_with_tokens` in `parse_source`. Returns `CstStage{ lex_failed: true, ... }` on tokenization error.

**Backward compat:** `src/incremental/incr_parser_db.mbt` removes the `CstStage` struct definition and adds `pub type CstStage = @pipeline.CstStage` so all existing callers of `@incremental.CstStage` continue to work unchanged.

---

## ✅ Task 1: Create `src/pipeline/moon.pkg`

**Files:**
- Create: `src/pipeline/moon.pkg`

```
import {
  "dowdiness/seam" @seam,
  "dowdiness/incr" @incr,
}
```

---

## ✅ Task 2: Create `src/pipeline/language.mbt`

**Files:**
- Create: `src/pipeline/language.mbt`

```moonbit
///|
/// Pipeline output of the grammar stage. Language-agnostic.
/// lex_failed: true when tokenization itself failed (no valid token stream).
/// Eq via CstNode's cached hash — O(1) rejection enables Memo backdating.
pub struct CstStage {
  cst         : @seam.CstNode
  diagnostics : Array[String]
  lex_failed  : Bool
} derive(Eq, Show)

///|
/// Partial trait: what a language implementor provides.
/// No type parameters — Token is hidden inside Self.
/// Returns CstStage directly; lex_failed signals tokenization failure.
pub(open) trait Language {
  parse_source(Self, String) -> CstStage
}

///|
/// Same-name struct: token-erased vtable for the pipeline.
/// Token is captured in closures at construction; only Ast is visible.
pub struct Language[Ast : Eq] {
  priv parse_source  : (String) -> CstStage
  priv to_ast        : (@seam.SyntaxNode) -> Ast
  priv on_lex_error  : (String) -> Ast
}

///|
/// Bridge: erase Token by capturing it inside closures.
pub fn[T : Language, Ast : Eq] Language::from(
  lang         : T,
  to_ast       : (@seam.SyntaxNode) -> Ast,
  on_lex_error : (String) -> Ast,
) -> Language[Ast] {
  {
    parse_source  : fn(s) { lang.parse_source(s) },
    to_ast,
    on_lex_error,
  }
}
```

---

## ✅ Task 3: Create `src/pipeline/parser_db.mbt`

**Files:**
- Create: `src/pipeline/parser_db.mbt`

```moonbit
///|
/// Language-agnostic Salsa-style incremental pipeline.
///
/// source_text : Signal[String]
///   → cst  : Memo[CstStage]  (calls lang.parse_source)
///   → term : Memo[Ast]       (reads cst_memo, calls lang.to_ast or lang.on_lex_error)
pub struct ParserDb[Ast : Eq] {
  priv source_text : @incr.Signal[String]
  priv cst_memo    : @incr.Memo[CstStage]
  priv term_memo   : @incr.Memo[Ast]
}

///|
pub fn[Ast : Eq] ParserDb::new(
  initial_source : String,
  lang           : Language[Ast],
) -> ParserDb[Ast] {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, initial_source, label="source_text")

  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage { (lang.parse_source)(source_text.get()) },
    label="cst",
  )

  let term_memo = @incr.Memo::new(
    rt,
    fn() -> Ast {
      let stage = cst_memo.get()  // registers dependency on cst_memo
      if stage.lex_failed {
        // Lex error: delegate to language's error representation
        let msg = if stage.diagnostics.length() > 0 { stage.diagnostics[0] } else { "lex error" }
        (lang.on_lex_error)(msg)
      } else {
        let syntax = @seam.SyntaxNode::from_cst(stage.cst)
        (lang.to_ast)(syntax)
      }
    },
    label="term",
  )
  { source_text, cst_memo, term_memo }
}

///|
pub fn[Ast : Eq] ParserDb::set_source(self : ParserDb[Ast], source : String) -> Unit {
  self.source_text.set(source)
}

///|
pub fn[Ast : Eq] ParserDb::cst(self : ParserDb[Ast]) -> CstStage {
  self.cst_memo.get()
}

///|
pub fn[Ast : Eq] ParserDb::diagnostics(self : ParserDb[Ast]) -> Array[String] {
  self.cst_memo.get().diagnostics.copy()
}

///|
pub fn[Ast : Eq] ParserDb::term(self : ParserDb[Ast]) -> Ast {
  self.term_memo.get()
}
```

---

## ✅ Task 4: Create `src/lambda/moon.pkg`

**Files:**
- Create: `src/lambda/moon.pkg`

```
import {
  "dowdiness/parser/pipeline",
  "dowdiness/parser/token",
  "dowdiness/parser/lexer",
  "dowdiness/parser/parser" @parse,
  "dowdiness/parser/ast",
  "dowdiness/seam" @seam,
}
```

---

## ✅ Task 5: Create `src/lambda/language.mbt`

**Files:**
- Create: `src/lambda/language.mbt`

```moonbit
///|
pub struct LambdaLanguage {}

///|
pub impl @pipeline.Language for LambdaLanguage with parse_source(_, s) {
  let tokens = @lexer.tokenize(s) catch {
    @lexer.TokenizationError(msg) => {
      let (empty_cst, _, _) = @parse.parse_cst_recover_with_tokens("", [], None)
      return @pipeline.CstStage::{
        cst: empty_cst,
        diagnostics: ["tokenization: " + msg],
        lex_failed: true,
      }
    }
  }
  let (cst, diags, _reuse_count) = @parse.parse_cst_recover_with_tokens(s, tokens, None)
  @pipeline.CstStage::{
    cst,
    diagnostics: diags.map(fn(d) {
      d.message + " [" + d.start.to_string() + "," + d.end.to_string() + "]"
    }),
    lex_failed: false,
  }
}

///|
/// Build a Language[AstNode] dictionary for the lambda calculus.
pub fn lambda_language() -> @pipeline.Language[@ast.AstNode] {
  @pipeline.Language::from(
    LambdaLanguage::{},
    to_ast       = fn(n) { @parse.syntax_node_to_ast_node(n, Ref::new(0)) },
    on_lex_error = fn(msg) { @ast.AstNode::error(msg, 0, 0) },
  )
}

///|
pub type LambdaParserDb = @pipeline.ParserDb[@ast.AstNode]

///|
pub fn LambdaParserDb::new(source : String) -> LambdaParserDb {
  @pipeline.ParserDb::new(source, lambda_language())
}
```

---

## ✅ Task 6: Update `src/incremental/` — re-export CstStage

**Files:**
- Modify: `src/incremental/moon.pkg` — add `"dowdiness/parser/pipeline"`
- Modify: `src/incremental/incr_parser_db.mbt`:
  - Remove the `CstStage` struct definition (lines defining the struct and its `derive`)
  - Add re-export so existing callers of `@incremental.CstStage` are unaffected:
    ```moonbit
    pub type CstStage = @pipeline.CstStage
    ```
  - Note: `TokenStage` stays in `incremental/` (lambda-specific, not moved)
  - Note: existing `ParserDb` struct and all its methods stay completely unchanged

---

## ✅ Task 7: Add tests for generic ParserDb

**Files:**
- Create: `src/pipeline/parser_db_test.mbt` (blackbox test)
- Create: `src/pipeline/moon.pkg` test imports (add `"dowdiness/parser/lambda"` under `for "test"`)

Tests to cover:
1. Warm path: repeated `term()` returns same value without re-parsing
2. Lex-error path: malformed source sets `lex_failed: true` in `cst_memo`, `term()` returns error node
3. Backdating: source change producing identical CST does not re-evaluate `term_memo`
4. `set_source` with same value is a no-op (Signal::Eq short-circuit)

Use `@lambda.LambdaParserDb::new` as the concrete implementation under test.

---

## ✅ Task 8: Update benchmarks

**Files:**
- Modify: `src/benchmarks/moon.pkg` — add `"dowdiness/parser/lambda"` to imports
- Optionally add one benchmark: `"lambda parserdb: cold"` using `@lambda.LambdaParserDb::new`

---

## Verification

```bash
moon check                                    # 0 errors, 0 warnings
moon test                                     # 343+ tests pass
moon bench --release                          # all benchmarks pass
moon info && git diff src/**/*.mbti           # verify public API additions are intentional
```

### Actual results (2026-02-26)

- `moon check` — 0 errors, 0 warnings ✅
- `moon test` — 78 tests passed (12 new in `src/lambda/`) ✅
- `moon bench --release` — 66/66 benchmarks passed (1 new: `lambda_parserdb: cold = 5.82 µs`) ✅

**Key deviation from plan:** MoonBit does not allow a `trait` and a `struct` with the same name in the
same namespace. The `trait Language` was renamed to `trait Parseable` (aligning with the existing
`incr/pipeline/pipeline_traits.mbt` vocabulary). The struct remains `Language[Ast]`. Callers use
`@pipeline.Language[Ast]` for the vtable and `@pipeline.Parseable` for the trait bound.
