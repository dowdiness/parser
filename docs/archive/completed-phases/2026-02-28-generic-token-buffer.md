# Generic TokenBuffer Implementation Plan

**Status:** Complete

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `TokenBuffer[T]` language-agnostic by parameterizing it on the token type `T`
and injecting the tokenizer as a closure, removing the hardcoded lambda dependencies.

**Architecture:** Two-step migration. First, replace the redundant `@token.TokenInfo`
concrete struct with a `typealias` for `@core.TokenInfo[Token]` — the generic version already
exists in `@core` and is structurally identical. This unifies the two types with zero callsite
churn. Second, generify `TokenBuffer` to `TokenBuffer[T]` by adding `tokenize_fn` + `eof_token`
injection fields; the update/index algorithm is already language-agnostic and moves unchanged.

**Tech Stack:** MoonBit, `moon` build tool

**Prerequisite:** Execute `docs/plans/2026-02-28-consolidate-lambda-v3.md` first. This plan
targets the post-v3 layout: `src/parser/` deleted, `src/lambda/` has all lambda-specific code,
`src/incremental/` is generic.

---

## Separation Boundary After This Plan

| File | `@token` dep? | Reason |
|------|--------------|--------|
| `src/lexer/token_buffer.mbt` | **No** | Generic `T`; algorithm is language-agnostic |
| `src/lexer/lexer.mbt` | Yes | `tokenize()` hardcodes `@token.Token` enum variants |
| `src/lambda/incremental.mbt` | Yes | Injects `@lexer.tokenize` + `@token.EOF` into `TokenBuffer` |

`@lexer` as a package still depends on `@token` via `tokenize()`. A future plan can move
`tokenize()` to `@lambda`, making `@lexer` depend only on `@core`.

---

## Task 1: Add `Eq` to `@core.TokenInfo[T]`

**Files:**
- Modify: `src/core/lib.mbt`

`@token.TokenInfo` had `derive(Show, Eq)`. After migrating to `@core.TokenInfo[@token.Token]`,
any equality comparison on token info requires `TokenInfo[T]` to propagate `Eq` from `T`.
Currently `@core.TokenInfo[T]` only derives `Show`.

**Step 1: Find the `TokenInfo[T]` struct in `src/core/lib.mbt`**

```bash
grep -n "struct TokenInfo" src/core/lib.mbt
```

Expected: one match around line 49.

**Step 2: Add `Eq` to the derive**

Change:
```moonbit
} derive(Show)
```
to:
```moonbit
} derive(Show, Eq)
```

**Step 3: Verify**

```bash
moon check && moon test
```

Expected: same pass count, zero failures. Adding `Eq` is purely additive.

**Step 4: Commit**

```bash
git add src/core/lib.mbt
git commit -m "feat(core): add Eq to TokenInfo[T]"
```

---

## Task 2: Replace `@token.TokenInfo` struct with `typealias`

`@core.TokenInfo[T]` already exists and is structurally identical to `@token.TokenInfo`.
Remove the duplicate struct and introduce a `typealias` so all existing callsites compile
unchanged. Only the two constructor calls (`@token.TokenInfo::new`) in `@lexer` need updating,
because `typealias` does not inherit constructors.

**Files:**
- Modify: `src/token/moon.pkg`
- Modify: `src/token/token.mbt`
- Modify: `src/lexer/moon.pkg`
- Modify: `src/lexer/lexer.mbt`
- Modify: `src/lexer/token_buffer.mbt`

**Step 1: Add `@core` import to `src/token/moon.pkg`**

Replace the empty file with:

```text
import {
  "dowdiness/parser/core" @core,
}
```

**Step 2: Replace the `TokenInfo` struct and constructor in `src/token/token.mbt`**

Remove these blocks:

```moonbit
///|
/// Token with source position information
pub(all) struct TokenInfo {
  token : Token
  start : Int // Start byte offset in source
  end : Int // End byte offset in source
} derive(Show, Eq)

///|
/// Create a new TokenInfo
pub fn TokenInfo::new(token : Token, start : Int, end : Int) -> TokenInfo {
  { token, start, end }
}
```

Replace with:

```moonbit
///|
/// Token with source position (alias for @core.TokenInfo[Token]).
/// @core.TokenInfo::new(token, start, end) is the constructor.
pub typealias TokenInfo = @core.TokenInfo[Token]
```

The functions `print_token_info` and `print_token_infos` reference `TokenInfo` by the local
alias name — their signatures resolve to `@core.TokenInfo[Token]` automatically. No change
needed to those functions.

Verify no struct literals exist in `@token`:
```bash
grep -n "TokenInfo {" src/token/token.mbt
```
Expected: zero results.

**Step 3: Confirm `src/lexer/moon.pkg` already has `@core`**

```bash
cat src/lexer/moon.pkg
```

If `@core` is not listed, add it:
```text
import {
  "dowdiness/parser/token",
  "dowdiness/parser/core" @core,
}
```

**Step 4: Replace `@token.TokenInfo::new` in `src/lexer/lexer.mbt`**

```bash
grep -n "@token.TokenInfo::new" src/lexer/lexer.mbt
```

For every occurrence, replace `@token.TokenInfo::new(` → `@core.TokenInfo::new(`.
Arguments are identical — `(token, start, end)`.

Also update the return type annotations in `tokenize_helper`, `tokenize`, and `tokenize_range`:
```moonbit
// Before:
) -> Array[@token.TokenInfo] raise TokenizationError

// After:
) -> Array[@core.TokenInfo[@token.Token]] raise TokenizationError
```

And any `Array[@token.TokenInfo]` local variable declarations:
```moonbit
// Before:
let result : Array[@token.TokenInfo] = []

// After:
let result : Array[@core.TokenInfo[@token.Token]] = []
```

**Step 5: Replace `@token.TokenInfo::new` in `src/lexer/token_buffer.mbt`**

```bash
grep -n "@token.TokenInfo::new" src/lexer/token_buffer.mbt
```

Apply the same substitution. Also update `Array[@token.TokenInfo]` type annotations to
`Array[@core.TokenInfo[@token.Token]]`.

**Step 6: Verify moon check and tests**

```bash
moon check && moon test
```

Expected: same pass count, zero failures. The `typealias` means `@token.TokenInfo` is still
a valid type everywhere — no callers break.

**Step 7: Commit**

```bash
git add src/token/ src/lexer/lexer.mbt src/lexer/token_buffer.mbt src/lexer/moon.pkg
git commit -m "refactor(token): replace TokenInfo struct with typealias for @core.TokenInfo[Token]"
```

---

## Task 3: Generify `TokenBuffer[T]`

**Files:**
- Modify: `src/lexer/token_buffer.mbt`

Replace the entire `src/lexer/token_buffer.mbt` with the generic version below.
Key changes from the current file:
- Struct gains `tokenize_fn` + `eof_token` fields; loses the direct `@token` dependency
- Constructor takes `tokenize_fn~` + `eof_token~` labeled parameters
- `tokenize_range(...)` call is replaced by an internal `tokenize_range_impl` method that
  calls `self.tokenize_fn` on the slice (relies on contract: EOF is always the last element)
- EOF push in `update` uses `self.eof_token` instead of hardcoded `@token.EOF`
- Helper functions (`find_left_index`, `find_right_index`, etc.) are generified with `[T]`

**Step 1: Replace `src/lexer/token_buffer.mbt`**

```moonbit
// Generic incremental token buffer for edit-aware lexing.
// T is the language-specific token type.
//
// Contract: tokenize_fn must always append an EOF sentinel as the last element.
// TokenBuffer::update relies on this when re-lexing a range: the last element
// of tokenize_fn(slice) is skipped during offset-adjustment.

///|
pub struct TokenBuffer[T] {
  priv tokenize_fn : (String) -> Array[@core.TokenInfo[T]] raise TokenizationError
  priv eof_token : T
  mut tokens : Array[@core.TokenInfo[T]]
  mut source : String
  mut version : Int
}

///|
pub fn[T] TokenBuffer::new(
  source : String,
  tokenize_fn~ : (String) -> Array[@core.TokenInfo[T]] raise TokenizationError,
  eof_token~ : T,
) -> TokenBuffer[T] raise TokenizationError {
  let tokens = tokenize_fn(source)
  { tokenize_fn, eof_token, tokens, source, version: 0 }
}

///|
pub fn[T] TokenBuffer::get_tokens(self : TokenBuffer[T]) -> Array[@core.TokenInfo[T]] {
  self.tokens
}

///|
pub fn[T] TokenBuffer::get_source(self : TokenBuffer[T]) -> String {
  self.source
}

///|
pub fn[T] TokenBuffer::get_version(self : TokenBuffer[T]) -> Int {
  self.version
}

///|
pub fn[T] TokenBuffer::update(
  self : TokenBuffer[T],
  edit : @core.Edit,
  new_source : String,
) -> Array[@core.TokenInfo[T]] raise TokenizationError {
  let old_tokens = self.tokens
  let old_len = old_tokens.length()
  if old_len == 0 {
    let tokens = (self.tokenize_fn)(new_source)
    self.tokens = tokens
    self.source = new_source
    self.version = self.version + 1
    return self.tokens
  }
  let eof_index = old_len - 1
  let mut left_index = find_left_index(old_tokens, edit.start)
  let mut right_index = find_right_index(old_tokens, edit.old_end())
  // Conservative: expand left by one token to catch boundary edits.
  if left_index > 0 {
    left_index = left_index - 1
  }
  if left_index > right_index {
    let tmp = right_index
    right_index = left_index
    left_index = tmp
  }
  if right_index < eof_index {
    right_index = right_index + 1
  }
  let mut left_offset_old = old_tokens[left_index].start
  if edit.start < left_offset_old {
    left_offset_old = edit.start
  }
  let mut right_offset_old = old_tokens[right_index].end
  if edit.old_end() > right_offset_old {
    right_offset_old = edit.old_end()
  }
  let left_offset_new = map_start_pos(left_offset_old, edit)
  let right_offset_new = map_end_pos(right_offset_old, edit)
  let new_len = new_source.length()
  let left_offset = clamp_offset(left_offset_new, new_len)
  let mut right_offset = clamp_offset(right_offset_new, new_len)
  if right_offset < left_offset {
    right_offset = left_offset
  }
  let replacement_tokens = self.tokenize_range_impl(
    new_source, left_offset, right_offset,
  )
  let new_tokens : Array[@core.TokenInfo[T]] = []
  for i = 0; i < left_index; i = i + 1 {
    new_tokens.push(old_tokens[i])
  }
  for token_info in replacement_tokens {
    new_tokens.push(token_info)
  }
  let delta = edit.delta()
  for i = right_index + 1; i < eof_index; i = i + 1 {
    let t = old_tokens[i]
    new_tokens.push(
      @core.TokenInfo::new(
        t.token,
        clamp_offset(t.start + delta, new_len),
        clamp_offset(t.end + delta, new_len),
      ),
    )
  }
  new_tokens.push(@core.TokenInfo::new(self.eof_token, new_len, new_len))
  self.tokens = new_tokens
  self.source = new_source
  self.version = self.version + 1
  self.tokens
}

///|
/// Re-lex a range of source. Tokenize the slice and offset-adjust results.
/// Skips the trailing EOF that tokenize_fn appends by contract (last element).
fn[T] TokenBuffer::tokenize_range_impl(
  self : TokenBuffer[T],
  source : String,
  start : Int,
  end : Int,
) -> Array[@core.TokenInfo[T]] raise TokenizationError {
  let slice = source[start:end] catch {
    _ => raise TokenizationError("Invalid range")
  }
  let slice_tokens = (self.tokenize_fn)(slice.to_string())
  // tokenize_fn contract: EOF is always last — skip it.
  let result : Array[@core.TokenInfo[T]] = []
  for i = 0; i < slice_tokens.length() - 1; i = i + 1 {
    let t = slice_tokens[i]
    result.push(@core.TokenInfo::new(t.token, t.start + start, t.end + start))
  }
  result
}

///|
fn[T] find_left_index(tokens : Array[@core.TokenInfo[T]], pos : Int) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  for i = 0; i < len; i = i + 1 {
    if tokens[i].end >= pos {
      return i
    }
  }
  len - 1
}

///|
fn[T] find_right_index(tokens : Array[@core.TokenInfo[T]], pos : Int) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  for i = len - 1; i >= 0; i = i - 1 {
    if tokens[i].start <= pos {
      return i
    }
  }
  0
}

///|
fn map_start_pos(pos : Int, edit : @core.Edit) -> Int {
  if pos <= edit.start {
    pos
  } else if pos >= edit.old_end() {
    pos + edit.delta()
  } else {
    edit.start
  }
}

///|
fn map_end_pos(pos : Int, edit : @core.Edit) -> Int {
  if pos < edit.start {
    pos
  } else if pos >= edit.old_end() {
    pos + edit.delta()
  } else {
    edit.new_end()
  }
}

///|
fn clamp_offset(pos : Int, length : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > length {
    length
  } else {
    pos
  }
}
```

**Step 2: Check `@lexer` package compiles**

```bash
moon check -p dowdiness/parser/lexer
```

Expected: `@lexer` compiles. Callers will show errors — fix in Task 4.

**DO NOT commit yet** — wait for Task 4 to restore a green build.

---

## Task 4: Update `TokenBuffer::new` callers

Three call sites need the new `tokenize_fn~` and `eof_token~` parameters. All three pass
`@lexer.tokenize` (or unqualified `tokenize` when inside `@lexer`) and `@token.EOF`.

**Files:**
- Modify: `src/lambda/incremental.mbt`
- Modify: `src/lexer/lexer_properties_test.mbt`
- Modify: `src/benchmarks/performance_benchmark.mbt`
- Modify: `src/benchmarks/moon.pkg`

**Step 1: Locate all `TokenBuffer::new` callsites**

```bash
grep -rn "TokenBuffer::new" src/
```

Expected: matches in `src/lambda/incremental.mbt`, `src/lexer/lexer_properties_test.mbt`,
and `src/benchmarks/performance_benchmark.mbt`.

**Step 2: Update `src/lambda/incremental.mbt`**

There are two `@lexer.TokenBuffer::new(source)` calls (in `full_parse` and `incremental_parse`).
Change each to:

```moonbit
@lexer.TokenBuffer::new(
  source,
  tokenize_fn=@lexer.tokenize,
  eof_token=@token.EOF,
)
```

**Step 3: Update `src/lexer/lexer_properties_test.mbt`**

Find `TokenBuffer::new(base,)` and `TokenBuffer::new(source)` (there are 3 occurrences).
Change each to:

```moonbit
TokenBuffer::new(
  base,
  tokenize_fn=tokenize,
  eof_token=@token.EOF,
)
```

(Inside `@lexer` tests, `tokenize` is unqualified and `@token.EOF` is accessible since
`@lexer/moon.pkg` imports `@token`.)

Also update the explicit `Result[TokenBuffer, ...]` type annotations to drop the
explicit type (let MoonBit infer `TokenBuffer[@token.Token]`):

```moonbit
// Before:
let buffer_res : Result[TokenBuffer, TokenizationError] = try? TokenBuffer::new(
  base,
)

// After (inferred):
let buffer_res = try? TokenBuffer::new(
  base,
  tokenize_fn=tokenize,
  eof_token=@token.EOF,
)
```

**Step 4: Add `@token` to `src/benchmarks/moon.pkg`**

After v3, benchmarks moon.pkg imports `@lexer` but not `@token`. Add the token package:

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

**Step 5: Update `src/benchmarks/performance_benchmark.mbt`**

```bash
grep -n "TokenBuffer::new" src/benchmarks/performance_benchmark.mbt
```

Change each `@lexer.TokenBuffer::new(source)` to:

```moonbit
@lexer.TokenBuffer::new(
  source,
  tokenize_fn=@lexer.tokenize,
  eof_token=@token.EOF,
)
```

**Step 6: Verify full build and tests**

```bash
moon check && moon test
```

Expected: same pass count as after v3, zero failures.

Verify benchmarks run:
```bash
moon bench --release -p dowdiness/parser/benchmarks
```

**Step 7: Commit Tasks 3 and 4 together**

```bash
git add src/lexer/token_buffer.mbt src/lambda/incremental.mbt \
        src/lexer/lexer_properties_test.mbt \
        src/benchmarks/performance_benchmark.mbt src/benchmarks/moon.pkg
git commit -m "refactor(lexer): generify TokenBuffer[T] with injected tokenize_fn + eof_token"
```

---

## Task 5: Update root facade, interfaces, format, docs

**Files:**
- Modify: `src/lib.mbt`
- Run: `moon info && moon fmt`
- Modify: `docs/README.md`

**Step 1: Update `src/lib.mbt` tokenize wrapper**

```bash
grep -n "fn tokenize" src/lib.mbt
```

Update the return type:

```moonbit
// Before:
pub fn tokenize(source : String) -> Array[@token.TokenInfo] raise {
  @lexer.tokenize(source)
}

// After:
pub fn tokenize(source : String) -> Array[@core.TokenInfo[@token.Token]] raise {
  @lexer.tokenize(source)
}
```

Verify `src/lib.mbt`'s `moon.pkg` imports `@core` (check with `cat src/moon.pkg`). Add it
if missing.

**Step 2: Run moon info and check interface diffs**

```bash
moon info
git diff src/**/*.mbti
```

Expected interface changes:
- `src/token/pkg.generated.mbti`: `TokenInfo` struct removed, `typealias TokenInfo = @core.TokenInfo[Token]` appears
- `src/lexer/pkg.generated.mbti`: `TokenBuffer` → `TokenBuffer[T]`, constructor gains labeled params
- `src/core/pkg.generated.mbti`: `TokenInfo[T]` shows `Eq` in impl list

**Step 3: Format**

```bash
moon fmt
```

**Step 4: Final test run**

```bash
moon test
```

Expected: all passing.

**Step 5: Archive plan and update docs/README.md**

Add `**Status:** Complete` near the top of this plan file, then:

```bash
git mv docs/plans/2026-02-28-generic-token-buffer.md \
       docs/archive/completed-phases/2026-02-28-generic-token-buffer.md
```

Update `docs/README.md`: move entry from Active Plans → Archive.

**Step 6: Validate docs**

```bash
bash check-docs.sh
```

Expected: no warnings.

**Step 7: Commit**

```bash
git add -A
git commit -m "chore: update interfaces, format, archive generic-token-buffer plan"
```

---

## Quick Verification Checklist

After all tasks complete:

```bash
# TokenBuffer is generic
grep -n "struct TokenBuffer" src/lexer/token_buffer.mbt
# → pub struct TokenBuffer[T]

# No @token references in token_buffer.mbt
grep -n "@token" src/lexer/token_buffer.mbt
# → zero results

# TokenInfo is a typealias in @token
grep -n "typealias TokenInfo" src/token/token.mbt
# → pub typealias TokenInfo = @core.TokenInfo[Token]

# tokenize() returns @core.TokenInfo
grep -n "fn tokenize" src/lexer/lexer.mbt
# → Array[@core.TokenInfo[@token.Token]]

# All tests pass
moon test
# → zero failures
```
