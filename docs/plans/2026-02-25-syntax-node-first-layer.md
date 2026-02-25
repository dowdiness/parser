# SyntaxNode-First Layer — Phase 2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate all direct `.cst` field access from outside `seam/`, store `SyntaxNode?` in `IncrementalParser` instead of `CstNode?`, and enforce the abstraction by making `.cst` private.

**Architecture:** Pure refactoring — no behavior changes. `cst_convert.mbt`'s free functions (`extract_token_text`, `tight_span`, `collect_binary_ops`, `extract_error_text`) are replaced by the SyntaxNode methods added in Phase 1. `IncrementalParser` replaces its `cst_tree: CstNode?` field with `syntax_tree: SyntaxNode?`. A `cst_node()` accessor is added to `SyntaxNode` so the reuse cursor (an internal parser concern) can still access the raw `CstNode`. Finally, `SyntaxNode.cst` is made private to enforce the boundary.

**Tech Stack:** MoonBit · `moon test` and `moon check` (from `parser/seam/` and `parser/src/` dirs) · `moon info && moon fmt` before final commit

---

### Prerequisite check

**Phase 1 must be complete.** Verify before starting:

```bash
cd /path/to/parser/seam && moon test
```

All tests must pass AND the following must be defined in `seam/pkg.generated.mbti`:
- `SyntaxToken` struct
- `SyntaxElement` enum
- `SyntaxNode::all_children`, `tokens`, `find_token`, `tokens_of_kind`, `tight_span`, `find_at`

If these are missing, implement Phase 1 first (`docs/plans/2026-02-25-syntax-node-extend.md`).

---

### Conventions to know

- Every top-level definition is preceded by `///|` on its own line.
- Tests are `test "description" { ... }` blocks inside `*_wbtest.mbt` (whitebox) or `*_test.mbt` (blackbox).
- Run tests from `src/` subdir: `cd /path/to/parser && moon test`.
- `seam/` is a **separate MoonBit module** — changes there are accessed as `@seam.SyntaxNode` from `src/`.
- `@syntax.WhitespaceToken.to_raw()` is the trivia kind used for whitespace filtering.
- This is a **pure refactoring**: all existing tests must keep passing, no new behavior.

---

### Task 1: Add `SyntaxNode::cst_node()` accessor to `seam/`

The `IncrementalParser` (in `src/`) needs to pass a `CstNode` to `make_reuse_cursor`. After `.cst` becomes private, the only way to get it will be through this accessor. Add it now so the later tasks can use it.

**Files:**
- Modify: `seam/syntax_node.mbt`
- Modify: `seam/syntax_node_wbtest.mbt`
- Modify: `seam/pkg.generated.mbti` (auto-generated — run `moon info`)

**Step 1: Write the failing test**

Add to `seam/syntax_node_wbtest.mbt`:

```moonbit
///|
test "SyntaxNode::cst_node returns underlying CstNode" {
  let cst = CstNode::new(RawKind(22), [])
  let sn = SyntaxNode::from_cst(cst)
  inspect(sn.cst_node() == cst, content="true")
}
```

**Step 2: Run to verify failure**

```bash
cd /path/to/parser/seam && moon test
```
Expected: compile error — `cst_node` not defined.

**Step 3: Implement** — add to `seam/syntax_node.mbt` after the existing methods:

```moonbit
///|
/// Returns the underlying `CstNode`.
///
/// **Advanced use only.** Use this when you need to pass the raw
/// `CstNode` to infrastructure that requires it (e.g. reuse cursors).
/// Prefer the SyntaxNode API for all navigation and position queries.
pub fn SyntaxNode::cst_node(self : SyntaxNode) -> CstNode {
  self.cst
}
```

**Step 4: Run tests**

```bash
cd /path/to/parser/seam && moon test
```
Expected: PASS.

**Step 5: Update `.mbti`**

```bash
cd /path/to/parser/seam && moon info && moon fmt
```

**Step 6: Commit**

```bash
git add seam/syntax_node.mbt seam/syntax_node_wbtest.mbt seam/pkg.generated.mbti
git commit -m "feat(seam): add SyntaxNode::cst_node accessor for reuse cursor"
```

---

### Task 2: Refactor `cst_convert.mbt` — replace free functions with SyntaxNode API

`cst_convert.mbt` contains four free functions that access `CstNode` directly: `extract_error_text`, `extract_token_text`, `tight_span`, `collect_binary_ops`. `convert_syntax_node` uses these via a `let g = node.cst` binding. Replace all of them with SyntaxNode method calls.

This is the largest change. Make it in two sub-steps: first eliminate the free functions, then clean up `let g = node.cst`.

**Files:**
- Modify: `src/parser/cst_convert.mbt`

**Step 1: Verify baseline — all tests pass before touching anything**

```bash
cd /path/to/parser && moon test
```
Expected: all tests PASS. If any fail, stop and investigate before proceeding.

**Step 2: Delete the four free functions**

Remove these function bodies entirely from `src/parser/cst_convert.mbt` (lines 1–81):
- `extract_error_text(cst : @seam.CstNode) -> String`
- `extract_token_text(cst : @seam.CstNode, token_kind : @seam.RawKind) -> String?`
- `tight_span(cst : @seam.CstNode, offset : Int) -> (Int, Int)`
- `collect_binary_ops(cst : @seam.CstNode) -> Array[@ast.Bop]`

**Step 3: Refactor `convert_syntax_node` — remove `let g = node.cst`**

Remove these two lines at the top of `convert_syntax_node`:
```moonbit
// DELETE these two lines:
let g = node.cst
let off = node.start()
```
Replace `off` references with `node.start()` and `g` references with SyntaxNode calls as described below.

**Step 4: Fix the match arm — `g.kind` → `node.kind()`**

```moonbit
// Old:
match @syntax.SyntaxKind::from_raw(g.kind) {

// New:
match @syntax.SyntaxKind::from_raw(node.kind()) {
```

**Step 5: Fix `IntLiteral` arm**

```moonbit
// Old:
@syntax.IntLiteral => {
  let text = extract_token_text(g, @syntax.IntToken.to_raw()).unwrap_or("")
  let value = @strconv.parse_int(text) catch { _ => 0 }
  let (tight_start, tight_end) = tight_span(g, off)
  ...
}

// New:
@syntax.IntLiteral => {
  let text = node.find_token(@syntax.IntToken.to_raw()).map(fn(t) { t.text() }).unwrap_or("")
  let value = @strconv.parse_int(text) catch { _ => 0 }
  let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(@syntax.WhitespaceToken.to_raw()))
  ...
}
```

**Step 6: Fix `VarRef` arm**

```moonbit
// Old:
@syntax.VarRef => {
  let name = extract_token_text(g, @syntax.IdentToken.to_raw()).unwrap_or("")
  let (tight_start, tight_end) = tight_span(g, off)
  ...
}

// New:
@syntax.VarRef => {
  let name = node.find_token(@syntax.IdentToken.to_raw()).map(fn(t) { t.text() }).unwrap_or("")
  let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(@syntax.WhitespaceToken.to_raw()))
  ...
}
```

**Step 7: Fix `LambdaExpr` arm**

```moonbit
// Old:
@syntax.LambdaExpr => {
  let param = extract_token_text(g, @syntax.IdentToken.to_raw()).unwrap_or("")
  let (tight_start, tight_end) = tight_span(g, off)
  ...
  @ast.AstNode::new(@ast.AstKind::Lam(param), tight_start, body.end, next_id(), [body])
  ...
  @ast.AstNode::new(@ast.AstKind::Lam(param), tight_start, tight_end, next_id(), [])
}

// New:
@syntax.LambdaExpr => {
  let param = node.find_token(@syntax.IdentToken.to_raw()).map(fn(t) { t.text() }).unwrap_or("")
  let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(@syntax.WhitespaceToken.to_raw()))
  ...
}
```

**Step 8: Fix `BinaryExpr` arm — replace `collect_binary_ops`**

```moonbit
// Old:
@syntax.BinaryExpr => {
  let ops = collect_binary_ops(g)
  ...
}

// New:
@syntax.BinaryExpr => {
  let ops : Array[@ast.Bop] = []
  for elem in node.all_children() {
    match elem {
      @seam.SyntaxElement::Token(t) =>
        if t.kind() == @syntax.PlusToken.to_raw() {
          ops.push(@ast.Bop::Plus)
        } else if t.kind() == @syntax.MinusToken.to_raw() {
          ops.push(@ast.Bop::Minus)
        }
      _ => ()
    }
  }
  ...
}
```

**Step 9: Fix `IfExpr` arm**

```moonbit
// Old:
@syntax.IfExpr => {
  let (tight_start, _) = tight_span(g, off)
  ...
  let if_end = if children.length() > 0 {
    children[children.length() - 1].end
  } else {
    off + g.text_len
  }
  ...
}

// New:
@syntax.IfExpr => {
  let (tight_start, _) = node.tight_span(trivia_kind=Some(@syntax.WhitespaceToken.to_raw()))
  ...
  let if_end = if children.length() > 0 {
    children[children.length() - 1].end
  } else {
    node.end()
  }
  ...
}
```

**Step 10: Fix `ParenExpr` arm**

```moonbit
// Old:
@syntax.ParenExpr => {
  let (tight_start, tight_end) = tight_span(g, off)
  ...
  @ast.AstNode::error("Empty ParenExpr", off, next_id())
}

// New:
@syntax.ParenExpr => {
  let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(@syntax.WhitespaceToken.to_raw()))
  ...
  @ast.AstNode::error("Empty ParenExpr", node.start(), next_id())
}
```

**Step 11: Fix `ErrorNode` arm — replace `extract_error_text`**

```moonbit
// Old:
@syntax.ErrorNode => {
  let (tight_start, tight_end) = tight_span(g, off)
  let text = extract_error_text(g)
  ...
}

// New:
@syntax.ErrorNode => {
  let (tight_start, tight_end) = node.tight_span(trivia_kind=Some(@syntax.WhitespaceToken.to_raw()))
  let parts : Array[String] = []
  for t in node.tokens() {
    if t.kind() != @syntax.WhitespaceToken.to_raw() && t.text() != "" {
      parts.push(t.text())
    }
  }
  let text = parts.join("")
  ...
}
```

**Step 12: Fix remaining `off` references in error fallback arms**

Search for any remaining `off` references in `convert_syntax_node` and replace with `node.start()`:
```moonbit
// Old:
@ast.AstNode::error("...", off, next_id())
// New:
@ast.AstNode::error("...", node.start(), next_id())
```

**Step 13: Run tests**

```bash
cd /path/to/parser && moon test
```
Expected: all existing tests PASS. If anything fails, check which arm was changed and compare with the original logic.

**Step 14: Commit**

```bash
git add src/parser/cst_convert.mbt
git commit -m "refactor(parser): replace cst_convert free functions with SyntaxNode methods"
```

---

### Task 3: Remove `parse_tree_from_tokens` duplicate parser path

`parse_tree_from_tokens` is a second, standalone token-level parser that builds `AstNode` directly without going through the CST. It is used in one place: `parse_with_error_recovery_tokens` in `error_recovery.mbt`. Replace that usage with the CST path.

**Files:**
- Modify: `src/parser/error_recovery.mbt`
- Modify: `src/parser/parser.mbt`

**Step 1: Replace the usage in `error_recovery.mbt`**

`parse_with_error_recovery_tokens` takes pre-tokenized input. Replace the `parse_tree_from_tokens` call with `parse_cst_recover_with_tokens` (which also accepts tokens):

```moonbit
// Old:
pub fn parse_with_error_recovery_tokens(
  tokens : Array[@token.TokenInfo],
) -> (@ast.AstNode, Array[String]) {
  let errors : Array[String] = []
  let tree = parse_tree_from_tokens(tokens) catch {
    ParseError(msg, token) => {
      let error_msg = "Parse error: " + msg + " at token " + @token.print_token(token)
      errors.push(error_msg)
      @ast.AstNode::error(error_msg, 0, 0)
    }
    e => {
      let error_msg = "Unexpected error: " + e.to_string()
      errors.push(error_msg)
      @ast.AstNode::error(error_msg, 0, 0)
    }
  }
  (tree, errors)
}

// New:
pub fn parse_with_error_recovery_tokens(
  tokens : Array[@token.TokenInfo],
) -> (@ast.AstNode, Array[String]) {
  let errors : Array[String] = []
  let (cst, diagnostics) = parse_cst_recover_with_tokens("", tokens, None)
  for diag in diagnostics {
    errors.push(
      "Parse error: " +
      diag.message +
      " (got " +
      @token.print_token(diag.got_token) +
      ")",
    )
  }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let tree = syntax_node_to_ast_node(syntax, Ref::new(0))
  (tree, errors)
}
```

> **Note:** `parse_cst_recover_with_tokens` takes a source string as its first argument. Passing `""` is correct here — the tokens already carry their text, and position information comes from `TokenInfo.start`/`.end` directly, not from the source string.

**Step 2: Run tests**

```bash
cd /path/to/parser && moon test
```
Expected: PASS.

**Step 3: Delete `parse_tree_from_tokens` from `parser.mbt`**

Remove the entire `parse_tree_from_tokens` function (lines 82–247 in `src/parser/parser.mbt`).

Also remove any helper functions that were only used by `parse_tree_from_tokens` — check if `make_parser`, `next_node_id`, `peek`, `peek_info`, `advance`, `expect` are used anywhere else. If they are only used inside `parse_tree_from_tokens`, delete them too.

**Step 4: Run `moon check`**

```bash
cd /path/to/parser && moon check
```
Expected: no errors. If any file still imports or calls `parse_tree_from_tokens`, fix it now.

**Step 5: Run tests**

```bash
cd /path/to/parser && moon test
```
Expected: all PASS.

**Step 6: Commit**

```bash
git add src/parser/parser.mbt src/parser/error_recovery.mbt
git commit -m "refactor(parser): remove duplicate parse_tree_from_tokens path"
```

---

### Task 4: Update `IncrementalParser` to store `SyntaxNode?`

Replace `cst_tree: CstNode?` with `syntax_tree: SyntaxNode?` throughout `incremental_parser.mbt`.

**Files:**
- Modify: `src/incremental/incremental_parser.mbt`

**Step 1: Update the struct field**

```moonbit
// Old:
pub struct IncrementalParser {
  ...
  mut cst_tree : @seam.CstNode?
  ...
}

// New:
pub struct IncrementalParser {
  ...
  mut syntax_tree : @seam.SyntaxNode?
  ...
}
```

**Step 2: Update `IncrementalParser::new`**

```moonbit
// Old:
{
  ...
  cst_tree: None,
  ...
}

// New:
{
  ...
  syntax_tree: None,
  ...
}
```

**Step 3: Update `IncrementalParser::parse` — store SyntaxNode instead of CstNode**

```moonbit
// Old (inside parse):
self.cst_tree = Some(cst)
...
let parsed_tree = @parse.cst_to_ast_node(cst, 0, Ref::new(0))

// New:
let syntax = @seam.SyntaxNode::from_cst(cst)
self.syntax_tree = Some(syntax)
...
let parsed_tree = @parse.syntax_node_to_ast_node(syntax, Ref::new(0))
```

Also update the error branches that reset `cst_tree` to `None`:
```moonbit
// Old:
self.cst_tree = None

// New:
self.syntax_tree = None
```

**Step 4: Update `incremental_reparse` — use SyntaxNode for cursor creation**

```moonbit
// Old:
let cursor = match self.cst_tree {
  Some(old_cst) =>
    Some(@parse.make_reuse_cursor(old_cst, damaged_range.start, damaged_range.end, tokens))
  None => None
}
...
self.cst_tree = Some(new_cst)
...
@parse.cst_to_ast_node(new_cst, 0, Ref::new(0))

// New:
let cursor = match self.syntax_tree {
  Some(old_syntax) =>
    Some(@parse.make_reuse_cursor(old_syntax.cst_node(), damaged_range.start, damaged_range.end, tokens))
  None => None
}
...
let new_syntax = @seam.SyntaxNode::from_cst(new_cst)
self.syntax_tree = Some(new_syntax)
...
@parse.syntax_node_to_ast_node(new_syntax, Ref::new(0))
```

**Step 5: Run tests**

```bash
cd /path/to/parser && moon test
```
Expected: all PASS, including incremental parser tests in `src/incremental/`.

**Step 6: Commit**

```bash
git add src/incremental/incremental_parser.mbt
git commit -m "refactor(incremental): store SyntaxNode instead of CstNode"
```

---

### Task 5: Make `SyntaxNode.cst` private

This is the enforcement step. Making `.cst` private will cause a compile error for any remaining direct field access from outside `seam/`. All such accesses should have been eliminated in Tasks 2–4.

**Files:**
- Modify: `seam/syntax_node.mbt`

**Step 1: Change the field visibility**

```moonbit
// Old:
pub struct SyntaxNode {
  cst : CstNode
  parent : SyntaxNode?
  offset : Int
} derive(Debug(ignore=[SyntaxNode]))

// New:
pub struct SyntaxNode {
  priv cst : CstNode
  parent : SyntaxNode?
  offset : Int
} derive(Debug(ignore=[SyntaxNode]))
```

> **Note on `derive(Debug)`:** If `derive(Debug(ignore=[SyntaxNode]))` fails to suppress the `parent: SyntaxNode?` field (because ignore applies to `SyntaxNode` not `SyntaxNode?`), also try `derive(Debug(ignore=[SyntaxNode, Option]))`. If derive doesn't work for this case, remove the `derive(Debug)` annotation entirely and add a manual `impl Debug for SyntaxNode` using the `Show` pattern.

**Step 2: Run `moon check` to catch any remaining `.cst` accesses**

```bash
cd /path/to/parser/seam && moon check
cd /path/to/parser && moon check
```
Expected: zero errors. If there are errors like `field cst is private`, that means a `.cst` access was missed — go fix it using the `cst_node()` accessor.

**Step 3: Run full test suite**

```bash
cd /path/to/parser && moon test
cd /path/to/parser/seam && moon test
```
Expected: all PASS.

**Step 4: Commit**

```bash
git add seam/syntax_node.mbt
git commit -m "refactor(seam): make SyntaxNode.cst private — enforces SyntaxNode API boundary"
```

---

### Task 6: Update interfaces, format, final verification

**Files:**
- Modify: `seam/pkg.generated.mbti` (auto-generated)
- Modify: `src/parser/pkg.generated.mbti` (auto-generated)

**Step 1: Update `.mbti` files and format**

```bash
cd /path/to/parser/seam && moon info && moon fmt
cd /path/to/parser && moon info && moon fmt
```

**Step 2: Review the diffs**

```bash
git diff seam/pkg.generated.mbti src/parser/pkg.generated.mbti
```

Verify:
- `SyntaxNode::cst_node()` appears in `seam/pkg.generated.mbti`
- `SyntaxNode.cst` field is no longer listed as public in `seam/pkg.generated.mbti`
- `parse_tree_from_tokens` is gone from `src/parser/pkg.generated.mbti`

**Step 3: Final full test run**

```bash
cd /path/to/parser && moon test
```
Expected: all tests PASS, zero failures.

**Step 4: Commit**

```bash
git add seam/pkg.generated.mbti src/parser/pkg.generated.mbti
git commit -m "chore: update interfaces after Phase 2 SyntaxNode-first refactor"
```
