# Dead Code Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the conceptual-only `src/crdt/` package and its traces from benchmarks, the root facade, and documentation, then complete the CLAUDE.md package map.

**Status:** Complete

**Architecture:** No logic changes — pure deletion + comment fixes. Every change is independently verifiable with `moon test` (353/353 passed — 18 crdt tests removed) and `bash check-docs.sh`.

**Tech Stack:** MoonBit (`moon test`, `moon info`, `moon fmt`), bash (`check-docs.sh`)

---

### Task 1: Delete `src/crdt/`

**Files:**
- Delete: `src/crdt/crdt_integration.mbt`
- Delete: `src/crdt/crdt_integration_test.mbt`
- Delete: `src/crdt/moon.pkg`

**Step 1: Delete the three files**

```bash
rm src/crdt/crdt_integration.mbt
rm src/crdt/crdt_integration_test.mbt
rm src/crdt/moon.pkg
rmdir src/crdt
```

**Step 2: Verify the directory is gone**

```bash
ls src/crdt 2>&1
```
Expected: `ls: cannot access 'src/crdt': No such file or directory`

---

### Task 2: Remove `@crdt` from `src/benchmarks/`

**Files:**
- Modify: `src/benchmarks/moon.pkg`
- Modify: `src/benchmarks/benchmark.mbt`
- Modify: `src/benchmarks/performance_benchmark.mbt`

**Step 1: Remove `@crdt` import from `src/benchmarks/moon.pkg`**

Current content of `src/benchmarks/moon.pkg`:
```
import {
  "dowdiness/parser/core" @core,
  "dowdiness/parser/lexer",
  "dowdiness/parser/parser" @parse,
  "dowdiness/parser/incremental",
  "dowdiness/parser/lambda" @lambda,
  "dowdiness/parser/crdt",
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
}
```

Remove the `"dowdiness/parser/crdt"` line. Result:
```
import {
  "dowdiness/parser/core" @core,
  "dowdiness/parser/lexer",
  "dowdiness/parser/parser" @parse,
  "dowdiness/parser/incremental",
  "dowdiness/parser/lambda" @lambda,
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
}
```

**Step 2: Remove four CRDT benchmark cases from `src/benchmarks/benchmark.mbt`**

Remove the following blocks (lines 132–195 in the current file). These are the four tests: `"ast to crdt"`, `"crdt to source"`, `"parsed document - parse"`, `"parsed document - edit"`:

```moonbit
///|
/// Benchmark: AST to CRDT conversion
test "ast to crdt" (b : @bench.T) {
  b.bench(fn() {
    let ast = @parse.parse_tree("λf.λx.f x") catch {
      _ => abort("benchmark failed")
    }
    let result = @crdt.ast_to_crdt(ast)
    b.keep(result)
  })
}

///|
/// Benchmark: CRDT to source reconstruction
test "crdt to source" (b : @bench.T) {
  b.bench(fn() {
    let ast = @parse.parse_tree("λf.λx.f x") catch {
      _ => abort("benchmark failed")
    }
    let crdt = @crdt.ast_to_crdt(ast)
    let result = @crdt.crdt_to_source(crdt)
    b.keep(result)
  })
}

///|
/// Benchmark: ParsedDocument - parse
test "parsed document - parse" (b : @bench.T) {
  b.bench(fn() {
    let doc = @crdt.ParsedDocument::new("42")
    doc.parse()
    b.keep(doc)
  })
}

///|
/// Benchmark: ParsedDocument - edit
test "parsed document - edit" (b : @bench.T) {
  b.bench(fn() {
    let doc = @crdt.ParsedDocument::new("x")
    doc.parse()
    let edit = @core.Edit::insert(1, 4)
    doc.edit(edit, "x + 1")
    b.keep(doc)
  })
}
```

**Step 3: Remove two CRDT benchmark cases from `src/benchmarks/performance_benchmark.mbt`**

Remove the following blocks (lines 177–205). These are: `"crdt operations - nested structure"` and `"crdt operations - round trip"`:

```moonbit
///|
/// Benchmark: CRDT operations - nested structure
test "crdt operations - nested structure" (b : @bench.T) {
  b.bench(fn() {
    let ast = @parse.parse_tree("λf.λx.if f x then x + 1 else x - 1") catch {
      _ => abort("benchmark failed")
    }
    let crdt = @crdt.ast_to_crdt(ast)
    let source = @crdt.crdt_to_source(crdt)
    b.keep(source)
  })
}

///|
/// Benchmark: CRDT operations - round trip
test "crdt operations - round trip" (b : @bench.T) {
  b.bench(fn() {
    let original = "λf.λx.f (f x)"
    let ast = @parse.parse_tree(original) catch {
      _ => abort("benchmark failed")
    }
    let crdt = @crdt.ast_to_crdt(ast)
    let reconstructed = @crdt.crdt_to_source(crdt)
    let ast2 = @parse.parse_tree(reconstructed) catch {
      _ => abort("benchmark failed")
    }
    b.keep(ast2)
  })
}
```

**Step 4: Run `moon check` to verify no remaining `@crdt` references**

```bash
moon check 2>&1
```
Expected: clean output, no errors.

**Step 5: Commit**

```bash
git add src/benchmarks/moon.pkg src/benchmarks/benchmark.mbt src/benchmarks/performance_benchmark.mbt
git commit -m "chore: remove CRDT benchmarks from src/benchmarks/"
```

---

### Task 3: Remove `@crdt` from the root facade (`src/moon.pkg` and `src/lib.mbt`)

**Files:**
- Modify: `src/moon.pkg`
- Modify: `src/lib.mbt`

**Step 1: Remove `"dowdiness/parser/crdt"` from `src/moon.pkg`**

Current content:
```
import {
  "dowdiness/parser/token",
  "dowdiness/parser/ast",
  "dowdiness/parser/lexer",
  "dowdiness/parser/parser" @parse,
  "dowdiness/parser/incremental",
  "dowdiness/parser/crdt",
  "dowdiness/parser/lambda" @lambda,
}
```

Remove the `"dowdiness/parser/crdt"` line. Result:
```
import {
  "dowdiness/parser/token",
  "dowdiness/parser/ast",
  "dowdiness/parser/lexer",
  "dowdiness/parser/parser" @parse,
  "dowdiness/parser/incremental",
  "dowdiness/parser/lambda" @lambda,
}
```

**Step 2: Update `src/lib.mbt`**

Two changes:

**(a) Fix the stale package comment block at the top.**

Current comment block (lines 3–17):
```moonbit
// This module re-exports the primary API entry points. For the full API,
// import subpackages directly:
//
//   dowdiness/parser/token        - Token, TokenInfo
//   dowdiness/parser/range        - Range
//   dowdiness/parser/edit         - Edit
//   dowdiness/parser/ast          - Ast, AstNode, AstKind, Bop
//   dowdiness/parser/lexer        - tokenize, TokenBuffer
//   dowdiness/parser/syntax       - CstNode, CstToken, SyntaxKind
//   dowdiness/parser/parser       - parse, parse_tree, parse_with_error_recovery
//   dowdiness/parser/incremental  - IncrementalParser, DamageTracker
//   dowdiness/parser/crdt         - CRDTNode, ParsedDocument
//   dowdiness/parser/viz          - DotNode (trait), to_dot[T : DotNode]
//   dowdiness/parser/lambda       - LambdaParserDb, LambdaLanguage, DotNode impl for AstNode
```

Replace with the accurate list (`range`/`edit` → `core`, `CstNode` attribution fixed, `crdt` removed):
```moonbit
// This module re-exports the primary API entry points. For the full API,
// import subpackages directly:
//
//   dowdiness/parser/token        - Token, TokenInfo
//   dowdiness/parser/core         - Edit, Range, ReuseSlot (shared primitives)
//   dowdiness/parser/ast          - AstNode, AstKind, Term, Bop
//   dowdiness/parser/lexer        - tokenize, TokenBuffer
//   dowdiness/parser/syntax       - SyntaxKind enum (token + node kind names)
//   dowdiness/parser/parser       - parse, parse_tree, parse_with_error_recovery
//   dowdiness/parser/incremental  - IncrementalParser, DamageTracker
//   dowdiness/parser/viz          - DotNode (trait), to_dot[T : DotNode]
//   dowdiness/parser/lambda       - LambdaParserDb, LambdaLanguage, DotNode impl for AstNode
//   dowdiness/parser/pipeline     - ParserDb — reactive incremental pipeline
```

**(b) Remove the CRDT re-export section (lines 64–76).**

Remove these lines entirely:
```moonbit
// ── CRDT ─────────────────────────────────────

///|
/// Convert a AST node tree to a CRDT representation.
pub fn ast_to_crdt(node : @ast.AstNode) -> @crdt.CRDTNode {
  @crdt.ast_to_crdt(node)
}

///|
/// Reconstruct source code from a CRDT tree.
pub fn crdt_to_source(node : @crdt.CRDTNode) -> String {
  @crdt.crdt_to_source(node)
}
```

**Step 3: Run `moon check`**

```bash
moon check 2>&1
```
Expected: clean, no errors.

**Step 4: Run `moon test`**

```bash
moon test 2>&1 | tail -5
```
Expected: `Total tests: 368, passed: 368, failed: 0.`
(Deleting `src/crdt/` removes its tests too — so the count will drop by however many tests were in `crdt_integration_test.mbt`. Verify it is the same count minus those tests, and that no previously-passing tests now fail.)

**Step 5: Regenerate interfaces**

```bash
moon info && moon fmt
```

**Step 6: Verify `src/pkg.generated.mbti` no longer references `@crdt`**

```bash
grep crdt src/pkg.generated.mbti
```
Expected: no output.

**Step 7: Commit**

```bash
git add src/moon.pkg src/lib.mbt src/pkg.generated.mbti
git commit -m "chore: remove src/crdt/ from root facade and regenerate interfaces"
```

---

### Task 4: Update CLAUDE.md package map

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add the three missing packages to the Package Map table**

Current table (lines 22–33):
```markdown
| Package | Purpose |
|---------|---------|
| `src/lexer/` | Tokenizer + incremental `TokenBuffer` |
| `src/parser/` | CST parser, CST→AST conversion, lambda `LanguageSpec` |
| `src/seam/` | Language-agnostic CST (`CstNode`, `SyntaxNode`, `EventBuffer`) |
| `src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable` — shared primitives |
| `src/ast/` | `AstNode`, `Term`, pretty-printer |
| `src/pipeline/` | `ParserDb` — reactive incremental pipeline |
| `src/incremental/` | `IncrementalParser`, damage tracking |
| `src/viz/` | DOT graph renderer (`DotNode` trait) |
| `src/lambda/` | Lambda-specific `LambdaLanguage`, `LambdaParserDb` |
```

Replace with (add `token`, `syntax`, `benchmarks`):
```markdown
| Package | Purpose |
|---------|---------|
| `src/token/` | `Token` enum + `TokenInfo` — the lambda token type (`T` in `ParserContext[T, K]`) |
| `src/syntax/` | `SyntaxKind` enum — symbolic kind names → `RawKind` integers for the CST |
| `src/lexer/` | Tokenizer + incremental `TokenBuffer` |
| `src/parser/` | CST parser, CST→AST conversion, lambda `LanguageSpec` |
| `src/seam/` | Language-agnostic CST (`CstNode`, `SyntaxNode`, `EventBuffer`) |
| `src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable` — shared primitives |
| `src/ast/` | `AstNode`, `Term`, pretty-printer |
| `src/pipeline/` | `ParserDb` — reactive incremental pipeline |
| `src/incremental/` | `IncrementalParser`, damage tracking |
| `src/viz/` | DOT graph renderer (`DotNode` trait) |
| `src/lambda/` | Lambda-specific `LambdaLanguage`, `LambdaParserDb` |
| `src/benchmarks/` | Performance benchmarks for all pipeline layers |
```

**Step 2: Update the test count in the Commands section**

The `moon test` comment on line 9 says `# 363 tests`. After removing `src/crdt/` tests, update it to the actual new count. Run `moon test` first, then update the comment to match:

```bash
moon test 2>&1 | grep "Total tests"
```

Update line 9 accordingly, e.g.:
```bash
moon test               # <N> tests
```

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md package map — add token/, syntax/, benchmarks/; remove crdt/"
```

---

### Task 5: Archive the plan and final verification

**Files:**
- Move: `docs/plans/2026-02-28-dead-code-audit-design.md` → `docs/archive/completed-phases/`
- Move: `docs/plans/2026-02-28-dead-code-audit.md` → `docs/archive/completed-phases/`
- Modify: `docs/README.md`

**Step 1: Mark both plan files as complete**

In `docs/plans/2026-02-28-dead-code-audit-design.md`, change `**Status:** Approved` to `**Status:** Complete`.

In `docs/plans/2026-02-28-dead-code-audit.md` (this file), insert `**Status:** Complete` after the `**Goal:**` line at the top.

After doing this, `bash check-docs.sh` will warn that both files need archiving — that is expected and is the trigger for Step 2.

**Step 2: Move both plan files to archive**

```bash
git mv docs/plans/2026-02-28-dead-code-audit-design.md docs/archive/completed-phases/
git mv docs/plans/2026-02-28-dead-code-audit.md docs/archive/completed-phases/
```

**Step 3: Update `docs/README.md`**

Move the active plan entry to the Archive section:

Remove from Active Plans:
```markdown
- [plans/2026-02-28-dead-code-audit-design.md](plans/2026-02-28-dead-code-audit-design.md) — remove `src/crdt/`, fix stale docs, complete package map
```

Add to Archive (Completed phase plans):
```markdown
- [archive/completed-phases/2026-02-28-dead-code-audit-design.md](archive/completed-phases/2026-02-28-dead-code-audit-design.md) — dead code audit design
- [archive/completed-phases/2026-02-28-dead-code-audit.md](archive/completed-phases/2026-02-28-dead-code-audit.md) — dead code audit implementation plan
```

Restore the Active Plans section to:
```markdown
## Active Plans (Future Work)

_(none — see archive for completed plans)_
```

**Step 4: Run full verification**

```bash
moon test 2>&1 | tail -5
bash check-docs.sh 2>&1
```

Both must be clean.

**Step 5: Final commit**

```bash
git add docs/plans/ docs/archive/completed-phases/ docs/README.md
git commit -m "chore: archive dead-code-audit plans after completion"
```
