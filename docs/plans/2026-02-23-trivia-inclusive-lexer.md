# Trivia-Inclusive Lexer Redesign Plan

> **Status:** Completed / Implemented 2026-02-23.
> Delivered via [PR #5](https://github.com/dowdiness/parser/pull/5) on branch
> `feature/trivia-inclusive-lexer`. Verified: 354/354 tests passing,
> 56/56 benchmarks. Additional fixes applied during implementation:
> `ReuseCursor` updated (see Scope below), `is_outside_damage` boundary
> corrected from `>` to `>=` to restore reuse of whitespace-prefixed atoms.

**Goal:** Redesign the lexer to emit whitespace (trivia) tokens directly,
eliminating the gap-synthesis workaround in `GreenParser` and removing the
double-read of whitespace bytes.

**Architecture:** Lexer emits all tokens including `Whitespace` in a single
scan. `GreenParser` absorbs trivia inline via `flush_trivia()` before each
syntactic token emission. `last_end` tracking and `emit_whitespace_before`
are removed entirely. Layers above the lexer (`GreenNode`, `build_tree`,
`ReuseCursor`, `token_count`) are unchanged — they already handle whitespace
via `trivia_kind`.

**Tech Stack:** MoonBit, existing `token`, `lexer`, `parser` packages.

---

## Motivation

Current approach has two problems:

1. **Double-read of whitespace bytes.** The lexer scans whitespace to find
   where it ends, then discards the content. `GreenParser::emit_whitespace_before`
   re-reads those same bytes via `source[last_end:info.start]` to recover the
   text. Every whitespace region is touched twice.

2. **Responsibility leak.** The lexer owns source scanning; `GreenParser` owns
   syntax structure. Gap synthesis mixes these concerns — `GreenParser` must
   track `last_end` and know how to extract whitespace from the raw source.

The rowan model (direct inspiration for this codebase's green/red tree) emits
trivia tokens from the lexer. This is the canonical fix.

---

## Scope: 5 files changed

| File | Change |
|---|---|
| `src/token/token.mbt` | Add `Whitespace` variant to `Token` enum |
| `src/lexer/lexer.mbt` | Emit `Whitespace` tokens instead of skipping whitespace |
| `src/lexer/token_buffer.mbt` | Verified — offset-based algorithm requires no code changes |
| `src/parser/green_parser.mbt` | Remove `last_end` + `emit_whitespace_before`; add `flush_trivia`; fix `byte_offset` in `try_reuse` to use WS start |
| `src/parser/reuse_cursor.mbt` | Add `new_follow_token()` for whitespace-aware follow-token lookup; remove dead `_token_pos`/`_node_token_count` params from `trailing_context_matches`; fix `is_outside_damage` boundary (`>` → `>=`) |

**Unchanged:** `GreenNode`, `GreenToken`, `build_tree`, `build_tree_interned`,
`IncrementalParser`, `token_count`, `RawKind`, `SyntaxKind`.

---

## Reference: Key Files

| File | Role |
|---|---|
| `src/token/token.mbt` | `Token` enum — needs `Whitespace` variant |
| `src/lexer/lexer.mbt` | `tokenize()` — core scan loop |
| `src/lexer/token_buffer.mbt` | `TokenBuffer::new`, `TokenBuffer::update` — incremental tokenizer |
| `src/parser/green_parser.mbt` | `GreenParser` struct, `emit_token`, `bump_error`, `parse_source_file` |

---

## Task 1: Add `Whitespace` to `Token` enum

**Files:**
- Modify: `src/token/token.mbt`
- Test: `src/token/*_test.mbt` (if exists)

**Step 1: Add variant**

```moonbit
pub enum Token {
  // ... existing variants unchanged ...
  Whitespace   // no payload — text lives in source[start:end]
}
```

No payload needed. Whitespace text is always recoverable from
`source[info.start:info.end]` since `TokenInfo` carries byte offsets.

**Step 2: Update `print_token` / `Show` impl if it exists**

Add a `Whitespace` arm returning `"whitespace"` or similar.

**Step 3: Run tests**

```bash
moon test --package dowdiness/parser/token
```

**Step 4: Commit**

```bash
git add src/token/token.mbt
git commit -m "feat(token): add Whitespace variant to Token enum"
```

---

## Task 2: Lexer emits whitespace tokens

**Files:**
- Modify: `src/lexer/lexer.mbt`
- Test: `src/lexer/*_test.mbt`

**Step 1: Write failing test**

```moonbit
test "tokenize includes whitespace tokens" {
  let tokens = @lexer.tokenize("x + 1") catch { _ => abort("failed") }
  // expect: [Ident("x"), Whitespace, Plus, Whitespace, Integer(1), EOF]
  //          or similar — whitespace tokens present between syntactic tokens
  inspect(tokens.length(), content="6")  // adjust to actual expected count
}
```

**Step 2: Modify scan loop**

Find the whitespace-skip block in `lexer.mbt`. Currently approximately:

```moonbit
// skip whitespace
while pos < source.length() && is_whitespace(source[pos]) {
  pos = pos + 1
}
```

Replace with:

```moonbit
// emit whitespace token
let ws_start = pos
while pos < source.length() && is_whitespace(source[pos]) {
  pos = pos + 1
}
if pos > ws_start {
  tokens.push(TokenInfo::new(Token::Whitespace, ws_start, pos))
}
```

**Step 3: Handle leading whitespace**

If the source starts with whitespace, it must now appear as the first entry
in the token array. Verify the scan loop handles position 0 correctly.

**Step 4: Run tests — expect failures in GreenParser tests**

```bash
moon test --package dowdiness/parser/lexer
```

Lexer-level tests should pass. Downstream failures (GreenParser, incremental)
are expected and will be fixed in Tasks 3–4.

**Step 5: Commit**

```bash
git add src/lexer/lexer.mbt
git commit -m "feat(lexer): emit Whitespace tokens instead of skipping"
```

---

## Task 3: Verify `TokenBuffer` handles whitespace entries

**Files:**
- Modify (if needed): `src/lexer/token_buffer.mbt`
- Test: `src/lexer/token_buffer_*test.mbt`

`TokenBuffer::update` finds the edit boundary and stable suffix using byte
offsets. Whitespace tokens carry correct `start`/`end` offsets so the
binary-search and suffix-scan logic should be **unchanged in algorithm**.

**Step 1: Read `token_buffer.mbt` and verify**

Check that no logic assumes the token array is whitespace-free (e.g. index
arithmetic, position counting). Look for any `position += 1` steps that
implicitly assume one token = one syntactic unit.

**Step 2: Update tests**

Token buffer tests that assert specific token array lengths or index positions
need updating. The array is now larger (whitespace entries present).

**Step 3: Run tests**

```bash
moon test --package dowdiness/parser/lexer
```

**Step 4: Commit**

```bash
git add src/lexer/token_buffer.mbt
git commit -m "fix(lexer): update TokenBuffer tests for whitespace-inclusive array"
```

---

## Task 4: Remove `last_end` and `emit_whitespace_before` from `GreenParser`

**Files:**
- Modify: `src/parser/green_parser.mbt`
- Test: `src/parser/*_test.mbt`

This is the largest change. The key design choice: **pull model** — `emit_token`
absorbs preceding trivia on demand via `flush_trivia()`.

**Step 1: Write failing test**

Verify a parse with leading/trailing/internal whitespace produces a green tree
whose leaf texts reconstruct the original source:

```moonbit
test "parse preserves whitespace in green tree" {
  let (tree, _) = @parse.parse_green_recover("  x + 1  ") catch {
    _ => abort("failed")
  }
  // concatenating all leaf token texts must equal original source
  let reconstructed = collect_leaf_texts(tree)
  inspect(reconstructed, content="  x + 1  ")
}
```

**Step 2: Add `flush_trivia`**

```moonbit
///|
/// Emit all consecutive Whitespace tokens at current position to the
/// event stream, advancing position past each one.
fn GreenParser::flush_trivia(self : GreenParser) -> Unit {
}
```

**Step 3: Update `emit_token`**

```moonbit
fn GreenParser::emit_token(self : GreenParser, kind : @syntax.SyntaxKind) -> Unit {
  self.flush_trivia()                    // absorb preceding whitespace
  let info = self.peek_info()
  let text = self.token_text(info)
  self.events.push(@green_tree.ParseEvent::Token(raw(kind), text))
  self.last_end = info.end              // remove this line too after flush_trivia works
  self.advance()
}
```

**Step 4: Update `bump_error`**

Same pattern — call `flush_trivia()` before emitting the error token.

**Step 5: Remove `last_end` and `emit_whitespace_before`**

Once `flush_trivia` drives whitespace emission:
- Delete `last_end : Int` field from `GreenParser`
- Delete `GreenParser::emit_whitespace_before` function
- Remove `self.last_end` assignments throughout
- Simplify trailing-whitespace block in `parse_source_file` — replace with
  `self.flush_trivia()` before the EOF check

**Step 6: Update `peek` to skip whitespace**

`peek()` is used by the grammar rules to check the next syntactic token.
It must skip `Whitespace` entries:

```moonbit
fn GreenParser::peek(self : GreenParser) -> @token.Token {
  let mut pos = self.position
  while pos < self.tokens.length() {
    match self.tokens[pos].token {
      @token.Whitespace => pos = pos + 1
      token => return token
    }
  }
  @token.EOF
}
```

`peek_info()` similarly needs a whitespace-skipping variant for the byte
offset used in `try_reuse`.

**Step 7: Run full test suite**

```bash
moon test
```

**Step 8: Commit**

```bash
git add src/parser/green_parser.mbt
git commit -m "refactor(parser): absorb trivia inline, remove last_end and emit_whitespace_before"
```

---

## Task 5: Update benchmarks and documentation

**Files:**
- Modify: `src/benchmarks/performance_benchmark.mbt` (if any benchmark
  inspects token array length or positions)
- Modify: `docs/benchmark_history.md` — add new snapshot after changes

Run the full benchmark suite and record results:

```bash
moon bench --package dowdiness/parser/benchmarks --release
```

Expected: full-parse benchmarks slightly faster (one source scan instead of
two for whitespace bytes). Incremental benchmarks neutral (TokenBuffer logic
unchanged). Construction benchmarks neutral.

---

## Key Design Decision: `flush_trivia` absorption model

Two models exist for how trivia attaches to the event stream:

| Model | When trivia is emitted | Rowan equivalent |
|---|---|---|
| **Pull (recommended)** | Just before the following syntactic token, inside `emit_token` | `bump()` absorbs leading trivia |
| **Push** | Just after the preceding syntactic token, inside `advance()` | `bump()` absorbs trailing trivia |

The pull model is recommended here because `emit_token` is already the single
syntactic emission point. All grammar rules go through it, so trivia absorption
happens correctly without changes to the grammar rule functions.

---

## What disappears

| Removed | Why |
|---|---|
| `GreenParser.last_end : Int` | No longer needed — lexer owns positions |
| `emit_whitespace_before()` | Replaced by `flush_trivia()` reading from token stream |
| `source[last_end:info.start]` slice in parser | Whitespace text comes from lexer's `TokenInfo` |
| Trailing-whitespace special case in `parse_source_file` | `flush_trivia()` before EOF handles it |
| Double-read of whitespace bytes | Single lexer scan |

---

## Notes

- `GreenParser.position` after this change steps over ALL tokens including
  whitespace. The `peek()` change ensures grammar rules still see only
  syntactic tokens.
- `ReuseCursor` now receives the whitespace-inclusive `tokens` array.
  `leading_token_matches` uses `first_token_kind`/`first_token_text` which skip
  whitespace internally. `trailing_context_matches` uses `new_follow_token`
  (added during implementation) which binary-searches by byte offset and skips
  whitespace, replacing the old index-arithmetic approach. `collect_old_tokens`
  filters whitespace and error tokens when building `old_tokens`.
- `IncrementalParser` builds `tokens` via `TokenBuffer::update`. The
  whitespace-inclusive array propagates naturally through to `ReuseCursor`.
