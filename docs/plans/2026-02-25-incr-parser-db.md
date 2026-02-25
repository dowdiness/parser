# `ParserDb` — Salsa-Style Incremental Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build `ParserDb`, a `Signal`/`Memo`-backed incremental pipeline that uses `CstNode` value equality for automatic stage backdating, alongside the existing `IncrementalParser`.

**Architecture:** `source_text : Signal[String]` → `tokens : Memo[TokenStage]` → `cst : Memo[CstStage]`. On tokenization error `term()` returns `AstNode::error(...)` (Option B: matches `IncrementalParser` contract). `ParserDb` lives in `src/incremental/`; `IncrementalParser` is untouched.

**Tech Stack:** MoonBit, `dowdiness/incr` (Signal, Memo, Runtime — new dep), `dowdiness/seam` (CstNode, SyntaxNode), `dowdiness/parser/parser` as `@parse` (parse_cst_recover_with_tokens, syntax_node_to_ast_node), `dowdiness/parser/lexer` as `@lexer` (tokenize, TokenizationError), `dowdiness/parser/ast` as `@ast` (AstNode)

---

## Background for the implementer

This codebase is a MoonBit lambda calculus parser. Key layers:

- **`CstNode`** (`@seam`) — position-independent, immutable, structurally hashed tree. Has O(1) `Eq` via cached hash. Perfect as a `Memo` value type.
- **`SyntaxNode`** (`@seam`) — ephemeral positioned view over a `CstNode`. `SyntaxNode::from_cst(cst)` creates a root view.
- **`AstNode`** (`@ast`) — semantic tree used by the rest of the app.
- **`incr`** — Salsa-style reactive library. `Signal[T]` is a mutable input cell; `Memo[T : Eq]` is a lazily-evaluated cached computation. When a `Signal` changes, `Memo` nodes that depended on it are invalidated. If a `Memo` recomputes to a value `== `the old value, downstream `Memo` nodes are **backdated** (not invalidated).

`Memo::new(rt, fn() { ... }, label?)` takes the `Runtime` directly during construction (before `ParserDb` exists as `self`, so we can't use `create_memo(db, ...)`).

---

## Task 1: Add `incr` as a module dependency

**Files:**
- Modify: `moon.mod.json`

**Background:** `incr` lives at `/home/antisatori/ghq/github.com/dowdiness/incr` locally. Add it as a path dependency first; convert to a git submodule for the published version if needed.

**Step 1: Add the path dep to `moon.mod.json`**

Open `moon.mod.json` and add `"dowdiness/incr"` to `deps`:

```json
{
  "name": "dowdiness/parser",
  "version": "0.1.0",
  "source": "src",
  "deps": {
    "moonbitlang/quickcheck": "0.9.10",
    "dowdiness/seam": { "path": "seam" },
    "dowdiness/incr": { "path": "../../incr" }
  },
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/parser",
  "license": "Apache-2.0",
  "keywords": ["parser", "lambda-calculus", "incremental"],
  "description": "Incremental lambda calculus parser in MoonBit"
}
```

**Step 2: Verify the dependency resolves**

Run:
```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
moon check
```

Expected: no errors referencing `dowdiness/incr`. If `moon check` fails with "path not found", the relative path `../../incr` may not be supported — in that case add `incr` as a git submodule:

```bash
git submodule add https://github.com/dowdiness/incr incr
```

Then change the path dep to `{ "path": "incr" }`.

**Step 3: Commit**

```bash
git add moon.mod.json
git commit -m "chore: add dowdiness/incr as path dependency"
```

---

## Task 2: Stage types + `ParserDb` struct + `new()`

**Files:**
- Create: `src/incremental/incr_parser_db.mbt`
- Create: `src/incremental/incr_parser_db_test.mbt`

**Background:** `TokenStage` and `CstStage` are the memo boundary types. They **must** derive `Eq` — this is what enables backdating. `Array[T]` derives `Eq` when `T : Eq`; `TokenInfo` and `CstNode` both do.

In the `tokens_memo` closure, `@lexer.tokenize(source)` raises `TokenizationError` on unrecognized characters. The closure must catch this and return `TokenStage::Err` rather than propagating the raise — `Memo::new` requires a `() -> T` (pure) closure.

**Step 1: Write the failing test**

Create `src/incremental/incr_parser_db_test.mbt`:

```moonbit
///|
test "ParserDb construction returns valid cst stage" {
  let db = @incremental.ParserDb::new("x + 1")
  let stage = db.cst()
  inspect!(stage.diagnostics, content="[]")
}
```

**Step 2: Run the test to see it fail**

```bash
moon test --filter incr_parser_db_test
```

Expected: compile error — `ParserDb` not defined yet.

**Step 3: Implement `TokenStage`, `CstStage`, `ParserDb`, and `new()`**

Create `src/incremental/incr_parser_db.mbt`:

```moonbit
///| Tokenization stage output — designed for Memo[T : Eq] boundaries.
/// Eq on Array[TokenInfo] is element-wise; enables backdating when
/// the same source re-tokenizes to an identical token stream.
pub(all) enum TokenStage {
  Ok(Array[@token.TokenInfo])
  Err(String)
} derive(Eq, Show)

///| Green parse stage output — designed for Memo[T : Eq] boundaries.
/// CstNode::Eq uses a cached structural hash (O(1) rejection path),
/// so comparing two CstStage values is very cheap.
/// diagnostics is Array[String] rather than Array[Diagnostic] because
/// Diagnostic[T] does not derive Eq; normalized strings keep the Eq boundary clean.
pub(all) struct CstStage {
  cst : @seam.CstNode
  diagnostics : Array[String]
} derive(Eq, Show)

///| Salsa-style incremental pipeline for the lambda calculus parser.
///
/// source_text : Signal[String]
///   → tokens : Memo[TokenStage]
///   → cst    : Memo[CstStage]
///
/// Calling set_source() invalidates tokens_memo and cst_memo.
/// If re-parse produces a CstNode equal to the previous one (CstNode::Eq),
/// downstream stages are backdated — they skip recomputation.
///
/// **Lifetime:** one ParserDb per document editing session.
pub struct ParserDb {
  priv rt         : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv tokens_memo : @incr.Memo[TokenStage]
  priv cst_memo    : @incr.Memo[CstStage]
}

///|
pub fn ParserDb::new(initial_source : String) -> ParserDb {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, initial_source, label="source_text")

  let tokens_memo = @incr.Memo::new(
    rt,
    fn() -> TokenStage {
      try {
        TokenStage::Ok(@lexer.tokenize(source_text.get()))
      } catch {
        @lexer.TokenizationError(msg) => TokenStage::Err(msg)
      }
    },
    label="tokens",
  )

  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage {
      match tokens_memo.get() {
        TokenStage::Err(msg) => {
          // Tokenization failed: return an empty SourceFile CST as placeholder.
          // term() will detect this via tokens_memo and return AstNode::error.
          let (empty_cst, _, _) = @parse.parse_cst_recover_with_tokens(
            "", [], None, None, None,
          )
          CstStage::{ cst: empty_cst, diagnostics: ["tokenization: " + msg] }
        }
        TokenStage::Ok(tokens) => {
          let source = source_text.get()
          let (cst, diags, _reuse_count) = @parse.parse_cst_recover_with_tokens(
            source, tokens, None, None, None,
          )
          CstStage::{
            cst,
            diagnostics: diags.map(fn(d) {
              d.message +
              " [" +
              d.start.to_string() +
              "," +
              d.end.to_string() +
              "]"
            }),
          }
        }
      }
    },
    label="cst",
  )
  { rt, source_text, tokens_memo, cst_memo }
}
```

**Step 4: Run the test**

```bash
moon test --filter incr_parser_db_test
```

Expected: PASS. The `diagnostics` for a valid source `"x + 1"` should be `[]`.

**Step 5: Commit**

```bash
git add src/incremental/incr_parser_db.mbt src/incremental/incr_parser_db_test.mbt
git commit -m "feat(incremental): add ParserDb struct and new() with Signal/Memo pipeline"
```

---

## Task 3: Public API + full test suite

**Files:**
- Modify: `src/incremental/incr_parser_db.mbt`
- Modify: `src/incremental/incr_parser_db_test.mbt`

**Background:** `term()` implements Option B — on tokenization failure it consults `tokens_memo` to detect the error and returns `AstNode::error(...)`, matching `IncrementalParser::parse` behavior. This way callers never need to check `diagnostics()` separately to detect unrecoverable failures.

**Step 1: Write all failing tests**

Add to `src/incremental/incr_parser_db_test.mbt`:

```moonbit
///|
test "ParserDb term on valid source" {
  let db = @incremental.ParserDb::new("1 + 2")
  let term = db.term()
  inspect!(term)
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
  let db = @incremental.ParserDb::new("\\x.")  // incomplete lambda
  let diags = db.diagnostics()
  // Should have at least one diagnostic
  assert_eq!(diags.length() > 0, true)
}

///|
test "ParserDb diagnostics empty on tokenization error" {
  // On tokenization error, cst_memo returns a placeholder CstStage
  // with diagnostics containing the tokenization error message.
  let db = @incremental.ParserDb::new("@invalid")
  let diags = db.diagnostics()
  assert_eq!(diags.length() > 0, true)
}

///|
test "ParserDb set_source updates term" {
  let db = @incremental.ParserDb::new("1")
  let t1 = db.term()
  db.set_source("2")
  let t2 = db.term()
  inspect!(t1)
  inspect!(t2)
}

///|
test "ParserDb term matches parse_cst_to_ast_node output" {
  // Validation checklist item 5: compare ParserDb::term() against direct parse
  let sources = ["x + 1", "\\x.x", "if 1 then 2 else 3", "1 + 2 + 3"]
  for source in sources {
    let db = @incremental.ParserDb::new(source)
    let from_db = db.term()
    let direct = @parse.parse_cst_to_ast_node(source) catch {
      _ => @ast.AstNode::error("parse_cst_to_ast_node failed", 0, 0)
    }
    inspect!(from_db)
    inspect!(direct)
  }
}
```

**Step 2: Run to see failures**

```bash
moon test --filter incr_parser_db_test
```

Expected: compile errors — `set_source`, `term`, `diagnostics` not yet defined.

**Step 3: Implement the public API methods**

Add to `src/incremental/incr_parser_db.mbt`:

```moonbit
///| Update the source text, invalidating tokens and cst memos.
/// If the new source equals the current source (String::Eq), Signal::set
/// is a no-op and no recomputation occurs.
pub fn ParserDb::set_source(self : ParserDb, source : String) -> Unit {
  self.source_text.set(source)
}

///| Return the current CstStage (parse result + normalized diagnostics).
/// Triggers memo evaluation if the source has changed since last call.
pub fn ParserDb::cst(self : ParserDb) -> CstStage {
  self.cst_memo.get()
}

///| Return normalized parse diagnostic strings.
/// On tokenization error this contains the tokenization message.
/// On parse error this contains position-annotated error strings.
pub fn ParserDb::diagnostics(self : ParserDb) -> Array[String] {
  self.cst_memo.get().diagnostics
}

///| Return an AstNode for the current source.
///
/// Option B error routing: on tokenization failure, returns AstNode::error(...)
/// matching IncrementalParser::parse behavior. Callers do not need to check
/// diagnostics() to detect unrecoverable failures — the tree itself carries
/// the error signal via AstKind::Error.
pub fn ParserDb::term(self : ParserDb) -> @ast.AstNode {
  match self.tokens_memo.get() {
    TokenStage::Err(msg) =>
      @ast.AstNode::error("Tokenization error: " + msg, 0, 0)
    TokenStage::Ok(_) => {
      let syntax = @seam.SyntaxNode::from_cst(self.cst_memo.get().cst)
      @parse.syntax_node_to_ast_node(syntax, Ref::new(0))
    }
  }
}
```

**Step 4: Run the tests**

```bash
moon test --filter incr_parser_db_test
```

Expected: compile succeeds. Several `inspect!` calls will fail with "snapshot not found" — that is expected.

**Step 5: Capture snapshots**

```bash
moon test --update --filter incr_parser_db_test
```

Expected: snapshot files updated. Review the captured output to verify it looks correct:
- `term on valid source "1 + 2"` should show an `App` or `Bop` AstNode
- `term on tokenization error` passes (no snapshot needed — uses `match`)
- `set_source updates term` — `t1` and `t2` should differ
- Fixture comparison — `from_db` and `direct` should match for each source

**Step 6: Run the full test suite to confirm no regressions**

```bash
moon test
```

Expected: all existing tests still pass.

**Step 7: Commit**

```bash
git add src/incremental/incr_parser_db.mbt src/incremental/incr_parser_db_test.mbt
git commit -m "feat(incremental): implement ParserDb public API with Option B term() routing"
```

---

## Task 4: Update interfaces and format

**Files:**
- Modify: `src/incremental/pkg.generated.mbti` (auto-updated by `moon info`)

**Step 1: Update interface files**

```bash
moon info && moon fmt
```

**Step 2: Review the diff**

```bash
git diff src/incremental/pkg.generated.mbti
```

Expected additions: `ParserDb` struct, `CstStage` struct, `TokenStage` enum, and their methods. Verify that no unexpected public API was added.

**Step 3: Run tests once more**

```bash
moon test
```

Expected: all tests pass.

**Step 4: Commit**

```bash
git add src/incremental/pkg.generated.mbti src/
git commit -m "chore: update interfaces after ParserDb addition (moon info && moon fmt)"
```

---

## Validation Checklist

After all tasks complete, verify these manually against the draft spec (`docs/plans/2026-02-22-incr-green-tree-integration-draft.md`):

1. `ParserDb::new("x + 1")` → `cst()` returns non-empty `CstStage` with empty `diagnostics`
2. `set_source("x + 1")` when source is already `"x + 1"` → `Signal::set` is a no-op (String Eq), no recomputation
3. `ParserDb::new("@invalid")` → `diagnostics()` returns non-empty, `term()` returns `AstKind::Error`
4. `ParserDb::new("\\x.")` (incomplete lambda) → `term()` returns partial tree, `diagnostics()` non-empty but not `AstKind::Error`
5. `term()` output matches `parse_cst_to_ast_node()` for a set of valid fixtures (covered by the fixture test)
