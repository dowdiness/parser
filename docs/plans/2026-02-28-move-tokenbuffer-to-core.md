# Move TokenBuffer[T] + LexError to @core

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split `src/lexer/` into generic infrastructure (`TokenBuffer[T]`, `LexError` → `@core`)
and lambda-specific code (`tokenize()` → stays in `@lexer`), so any future language can use
incremental lexing without depending on lambda's tokenizer.

**Architecture:** Pure mechanical rename — no algorithm changes anywhere. `LexError` replaces
`TokenizationError` (same `String` payload, same usage pattern). `TokenBuffer[T]` moves from
`src/lexer/token_buffer.mbt` to `src/core/token_buffer.mbt`; its internal `@core.` prefixes
become unqualified (same package). The compiler (`moon check`) guides completeness — every
missed site is a type error.

**Tech Stack:** MoonBit, `moon` build tool

---

## Why this matters

Currently `@lexer` owns both:
- `tokenize()` — knows lambda characters, imports `@token` (lambda-specific)
- `TokenBuffer[T]` — edit-aware incremental buffer, knows nothing about lambda (generic)

Any future language wanting incremental lexing must import `@lexer`, which drags in
`TokenizationError` and the lambda tokenizer. After this change, a Python or SQL language
only needs `@core` for the buffer infrastructure.

```
BEFORE: new-lang → @lexer (TokenBuffer, TokenizationError, lambda tokenizer)
AFTER:  new-lang → @core  (TokenBuffer, LexError)
        @lexer   → @core  (declares tokenize() raising @core.LexError)
```

---

## Baseline

```bash
moon test   # must show 371 tests, 0 failures before starting
```

---

## Task 1: Add `pub suberror LexError` to `src/core/lib.mbt`

No behavior changes. One new declaration.

**Files:**
- Modify: `src/core/lib.mbt`

**Step 1: Add LexError after the existing Diagnostic struct**

In `src/core/lib.mbt`, locate the `Diagnostic[T]` struct (around line 58) and add immediately
after its closing `} derive(Show)` line:

```moonbit
///|
/// Lex error raised by a tokenize_fn when the source contains unrecognizable input.
/// Generic replacement for language-specific tokenization error types.
pub suberror LexError {
  LexError(String)
}
```

**Step 2: Verify**

```bash
moon check
moon test
```

Expected: 371 tests, 0 failures. No behavior changed.

**Step 3: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add LexError suberror — generic replacement for TokenizationError"
```

---

## Task 2: Move `token_buffer.mbt` to `src/core/`, update internal references

Copy the file, remove all `@core.` prefixes (same package now), rename `TokenizationError`
→ `LexError`. `src/core/moon.pkg` needs no changes — `TokenBuffer` only uses types already
in `@core` (`TokenInfo`, `Edit`, `LexError`).

**Files:**
- Create: `src/core/token_buffer.mbt` (from `src/lexer/token_buffer.mbt`)
- Keep: `src/lexer/token_buffer.mbt` (delete in Task 3)

**Step 1: Copy the file**

```bash
cp src/lexer/token_buffer.mbt src/core/token_buffer.mbt
```

**Step 2: Update `src/core/token_buffer.mbt`**

Apply these substitutions throughout the file:

| Old | New |
|-----|-----|
| `@core.TokenInfo[T]` | `TokenInfo[T]` |
| `@core.TokenInfo::new(` | `TokenInfo::new(` |
| `@core.Edit` | `Edit` |
| `TokenizationError` | `LexError` |

The struct definition becomes:

```moonbit
pub struct TokenBuffer[T] {
  priv tokenize_fn : (String) -> Array[TokenInfo[T]] raise LexError
  priv eof_token : T
  mut tokens : Array[TokenInfo[T]]
  mut source : String
  mut version : Int
}
```

The constructor becomes:

```moonbit
pub fn[T] TokenBuffer::new(
  source : String,
  tokenize_fn~ : (String) -> Array[TokenInfo[T]] raise LexError,
  eof_token~ : T,
) -> TokenBuffer[T] raise LexError {
  let tokens = tokenize_fn(source)
  { tokenize_fn, eof_token, tokens, source, version: 0 }
}
```

The `update` signature becomes:

```moonbit
pub fn[T] TokenBuffer::update(
  self : TokenBuffer[T],
  edit : Edit,
  new_source : String,
) -> Array[TokenInfo[T]] raise LexError {
```

The internal `tokenize_range_impl` becomes:

```moonbit
fn[T] TokenBuffer::tokenize_range_impl(
  self : TokenBuffer[T],
  source : String,
  start : Int,
  end : Int,
) -> Array[TokenInfo[T]] raise LexError {
  let slice = source[start:end] catch {
      _ => raise LexError("Invalid range")
    }
  let slice_tokens = (self.tokenize_fn)(slice.to_string())
  let result : Array[TokenInfo[T]] = []
  for i = 0; i < slice_tokens.length() - 1; i = i + 1 {
    let t = slice_tokens[i]
    result.push(TokenInfo::new(t.token, t.start + start, t.end + start))
  }
  result
}
```

The `new_tokens` local variable inside `update`:

```moonbit
  let new_tokens : Array[TokenInfo[T]] = []
```

The two `TokenInfo::new(` calls inside the offset-adjust loop and EOF push stay the same
(just remove `@core.` prefix from `@core.TokenInfo::new(`).

**Step 3: Verify — `@core` side compiles, `@lexer` still has its own copy**

```bash
moon check -p dowdiness/parser/core
```

Expected: no errors (both copies exist, no conflict yet).

**Step 4: Commit**

```bash
git add src/core/token_buffer.mbt
git commit -m "feat(core): add TokenBuffer[T] to @core (copy from @lexer, de-prefixed)"
```

---

## Task 3: Update `src/lexer/lexer.mbt` and delete `src/lexer/token_buffer.mbt`

Remove `TokenizationError` from `@lexer` (now in `@core`). Update all raise sites and
function signatures in `lexer.mbt`. Delete the old `token_buffer.mbt` copy.

**Files:**
- Modify: `src/lexer/lexer.mbt`
- Delete: `src/lexer/token_buffer.mbt`

**Step 1: Remove `TokenizationError` declaration from `src/lexer/lexer.mbt`**

Delete these lines (currently lines 3–6):

```moonbit
///|
pub suberror TokenizationError {
  TokenizationError(String)
}
```

**Step 2: Update raise sites and function signatures in `src/lexer/lexer.mbt`**

Apply these substitutions:

| Old | New |
|-----|-----|
| `raise TokenizationError(` | `raise @core.LexError(` |
| `) raise TokenizationError` | `) raise @core.LexError` |

There are 2 `raise TokenizationError(...)` call sites and 3 function declarations with
`raise TokenizationError` in their return type. Run after each substitution:

```bash
moon check -p dowdiness/parser/lexer
```

**Step 3: Delete the old `token_buffer.mbt`**

```bash
rm src/lexer/token_buffer.mbt
```

**Step 4: Verify**

```bash
moon check
moon test
```

Expected: 371 tests, 0 failures. `@lexer` now only contains lambda tokenizer code.

**Step 5: Commit**

```bash
git add src/lexer/lexer.mbt
git rm src/lexer/token_buffer.mbt
git commit -m "refactor(lexer): remove TokenizationError (moved to @core.LexError); delete token_buffer.mbt"
```

---

## Task 4: Update all external catch sites and qualifier changes

`moon check` will report every site that still references `@lexer.TokenizationError` or
`@lexer.TokenBuffer`. Fix them file by file.

**Files:**
- Modify: `src/incremental/incremental_parser.mbt`
- Modify: `src/lambda/language.mbt`
- Modify: `src/parser/cst_parser.mbt`
- Modify: `src/parser/error_recovery.mbt`
- Modify: `src/lexer/lexer_test.mbt`
- Modify: `src/lexer/lexer_properties_test.mbt`
- Modify: `src/benchmarks/performance_benchmark.mbt`

**Step 1: Run moon check to see all errors**

```bash
moon check 2>&1 | grep "error\|TokenizationError\|TokenBuffer"
```

Work through each file below.

**Step 2: `src/incremental/incremental_parser.mbt`**

Three substitutions:

| Old | New |
|-----|-----|
| `@lexer.TokenBuffer[@token.Token]?` | `@core.TokenBuffer[@token.Token]?` |
| `@lexer.TokenBuffer::new(` | `@core.TokenBuffer::new(` |
| `@lexer.TokenizationError(msg)` | `@core.LexError(msg)` |

The struct field (line ~27):
```moonbit
  mut token_buffer : @core.TokenBuffer[@token.Token]?
```

Two constructor calls in `parse()` and `edit()`:
```moonbit
    let buffer = @core.TokenBuffer::new(
      self.source,
      tokenize_fn=@lexer.tokenize,
      eof_token=@token.EOF,
    )
```

Three catch arms (lines ~96, ~128, ~146):
```moonbit
  } catch {
    @core.LexError(msg) => {
```

**Step 3: `src/lambda/language.mbt`**

One catch arm (currently unqualified since `@lexer` was imported):
```moonbit
  } catch {
    @core.LexError(msg) => {
```

**Step 4: `src/parser/cst_parser.mbt`**

One return type annotation:
```moonbit
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
```

**Step 5: `src/parser/error_recovery.mbt`**

One catch arm:
```moonbit
  } catch {
    @core.LexError(msg) => {
```

**Step 6: `src/lexer/lexer_test.mbt`**

One catch arm (currently unqualified `TokenizationError` within the `@lexer` package's test):
```moonbit
  } catch {
    @core.LexError(_) => true
  }
```

**Step 7: `src/lexer/lexer_properties_test.mbt`**

Six `Result[..., TokenizationError]` type annotations → `Result[..., @core.LexError]`:
```moonbit
          let updated_res : Result[
            Array[@token.TokenInfo[@token.Token]],
            @core.LexError,
          ] = try? buffer.update(edit, new_source)
          let full_res : Result[
            Array[@token.TokenInfo[@token.Token]],
            @core.LexError,
          ] = try? tokenize(new_source)
```

**Step 8: `src/benchmarks/performance_benchmark.mbt`**

Three `@lexer.TokenBuffer::new(` → `@core.TokenBuffer::new(` (the `tokenize_fn` and
`eof_token` arguments stay the same):

```moonbit
    let buf = @core.TokenBuffer::new(
      source,
      tokenize_fn=@lexer.tokenize,
      eof_token=@token.EOF,
    )
```

**Step 9: Verify**

```bash
moon check
moon test
```

Expected: 371 tests, 0 failures. Zero `@lexer.TokenizationError` or `@lexer.TokenBuffer`
references remain:

```bash
grep -rn "@lexer\.TokenizationError\|@lexer\.TokenBuffer" src/
# → zero results
```

**Step 10: Commit**

```bash
git add src/incremental/incremental_parser.mbt \
        src/lambda/language.mbt \
        src/parser/cst_parser.mbt \
        src/parser/error_recovery.mbt \
        src/lexer/lexer_test.mbt \
        src/lexer/lexer_properties_test.mbt \
        src/benchmarks/performance_benchmark.mbt
git commit -m "refactor: update all catch sites and qualifiers — TokenizationError → @core.LexError, @lexer.TokenBuffer → @core.TokenBuffer"
```

---

## Task 5: Update v3 plan, interfaces, format, docs

**Files:**
- Modify: `docs/plans/2026-02-28-consolidate-lambda-v3.md`
- Modify: `docs/README.md`

**Step 1: Update v3 plan — Task 2's `parse_cst_recover` return type**

In the v3 plan's Task 2 Step 4, `parse_cst_recover` function signature, change:

```moonbit
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @lexer.TokenizationError {
```
to:
```moonbit
) -> (@seam.CstNode, Array[@core.Diagnostic[@token.Token]]) raise @core.LexError {
```

**Step 2: Update v3 plan — Task 5's `lambda_incremental_language()` code**

In the v3 plan's Task 5 Step 2, three changes in the `lambda_incremental_language()` code block:

a) The `token_buf` declaration:
```moonbit
  let token_buf : Ref[@core.TokenBuffer[@token.Token]?] = Ref::new(None)
```

b) Two catch arms (in `full_parse` and in the `None` arm of `incremental_parse`):
```moonbit
      } catch {
        @core.LexError(msg) => {
```

**Step 3: Update interfaces and format**

```bash
moon info
git diff src/**/*.mbti
```

Expected changes:
- `src/core/pkg.generated.mbti` gains `TokenBuffer[T]`, `LexError`
- `src/lexer/pkg.generated.mbti` loses `TokenBuffer[T]`, `TokenizationError`

```bash
moon fmt
```

**Step 4: Final full test**

```bash
moon test
```

Expected: 371 tests, 0 failures.

**Step 5: Update `docs/README.md`**

Add this plan to the Active Plans section:
```
- [`plans/2026-02-28-move-tokenbuffer-to-core.md`](plans/2026-02-28-move-tokenbuffer-to-core.md) — Move TokenBuffer[T] + LexError to @core for multi-language support
```

**Step 6: Commit**

```bash
git add src/**/*.mbti \
        docs/plans/2026-02-28-consolidate-lambda-v3.md \
        docs/README.md
git commit -m "chore: update interfaces, format, update v3 plan for @core.LexError, update docs index"
```

---

## Quick Verification Checklist

After all tasks complete:

```bash
# TokenBuffer and LexError now in @core
grep -n "TokenBuffer\|LexError" src/core/pkg.generated.mbti
# → both present

# @lexer no longer exports TokenBuffer or TokenizationError
grep -n "TokenBuffer\|TokenizationError" src/lexer/pkg.generated.mbti
# → zero results

# No cross-language coupling remaining
grep -n "token\|syntax\|ast" src/core/moon.pkg
# → zero results (enforced: @core has no language imports)

# All tests pass
moon test
# → 371 passing, 0 failures
```
