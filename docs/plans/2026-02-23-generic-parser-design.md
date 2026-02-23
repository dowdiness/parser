# Generic Parser Framework Design

**Date:** 2026-02-23
**Status:** Approved
**Goal:** Extract a reusable `parser-core` library so other MoonBit projects can define their own language parsers with minimum effort, reusing the green tree, incremental parsing, and error recovery infrastructure.

---

## Motivation

The current `parser/` module is hardcoded for Lambda Calculus. The green tree layer (`green-tree/`) is already language-agnostic (`RawKind` is a plain `Int` wrapper). The only language-specific parts are:

- `syntax/syntax_kind.mbt` — Lambda token/node kinds
- `token/token.mbt` — Lambda `Token` enum
- `lexer/lexer.mbt` — Lambda character rules
- `term/term.mbt` — Lambda AST types
- `parser/green_parser.mbt` — Lambda grammar rules

The goal is to parameterize these so any language author gets incremental parsing, structural sharing, error recovery, and subtree reuse for free.

---

## Phase 1: Explicit ParserContext API

Phase 2 (combinators + arena/static allocation) is designed to layer on top with zero breaking changes.

---

## Package Structure

Two repos, following the existing submodule pattern:

```
dowdiness/parser-core    (new repo — generic toolkit)
  src/
    context/             — ParserContext[T, K], LanguageSpec[T, K]
    tokenizer/           — generic TokenInfo[T]
    diagnostic/          — generic Diagnostic struct
    lib.mbt              — public API: parse_with, parse_with_recover

dowdiness/parser         (current repo — becomes reference implementation)
  moon.mod.json          — adds parser-core as dependency
  src/
    syntax/              — SyntaxKind (Lambda-specific, unchanged)
    token/               — Token (unchanged)
    lexer/               — tokenize() (unchanged)
    term/                — Term, TermNode (unchanged)
    parser/              — grammar functions, adapted to ParserContext API
    green-tree/          — shared dependency (already generic)
    incremental/         — damage tracking (stays here)
```

The `green-tree/` package stays as a shared dependency of both `parser-core` and `parser`.

---

## Core Abstractions

### `TokenInfo[T]`

Generic replacement for the current `@token.TokenInfo`:

```moonbit
pub struct TokenInfo[T] {
  token : T
  start : Int   // byte offset, inclusive
  end   : Int   // byte offset, exclusive
}
```

### `LanguageSpec[T, K]`

A record of functions describing one language. Created **once at module init**, reused across all parses — zero per-parse allocation.

```moonbit
pub struct LanguageSpec[T, K] {
  kind_to_raw     : (K) -> @green_tree.RawKind
  token_is_eof    : (T) -> Bool
  tokens_equal    : (T, T) -> Bool   // needed for expect()
  whitespace_kind : K
  eof_token       : T
}
```

The "record of functions" pattern (common in OCaml, Go interfaces) is used instead of a trait with associated types. This avoids uncertainty about MoonBit's associated-type support while remaining type-safe — `T` and `K` are real type parameters.

`tokens_equal` is required because a generic `T` has no guaranteed `Eq` constraint. The current parser uses `==` on the concrete `Token` enum; the generic version passes equality explicitly.

### `ParserContext[T, K]`

The stable primitive surface. Grammar functions write against this API exclusively — it is the contract that makes Phase 2 combinators possible without breaking existing grammar code.

```moonbit
pub struct ParserContext[T, K] {
  spec           : LanguageSpec[T, K]
  tokens         : Array[TokenInfo[T]]
  source         : String
  mut position   : Int
  mut last_end   : Int
  events         : @green_tree.EventBuffer
  errors         : Array[Diagnostic]
  mut error_count : Int
  cursor         : ReuseCursor?
  mut open_nodes  : Int
}
```

**The 9 methods grammar code uses** (direct equivalents of today's `GreenParser` methods):

```moonbit
fn peek(ctx : ParserContext[T, K]) -> T
fn at(ctx : ParserContext[T, K], token : T) -> Bool
fn emit_token(ctx : ParserContext[T, K], kind : K) -> Unit
fn start_node(ctx : ParserContext[T, K], kind : K) -> Unit
fn finish_node(ctx : ParserContext[T, K]) -> Unit
fn mark(ctx : ParserContext[T, K]) -> Int
fn start_at(ctx : ParserContext[T, K], mark : Int, kind : K) -> Unit
fn error(ctx : ParserContext[T, K], msg : String) -> Unit
fn bump_error(ctx : ParserContext[T, K]) -> Unit
```

---

## Public Parse API

```moonbit
/// Parse a source string — returns green tree + diagnostics.
pub fn parse_with[T, K](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]] raise,
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@green_tree.GreenNode, Array[Diagnostic]) raise

/// Parse with pre-built tokens and optional reuse cursor (incremental path).
pub fn parse_with_cursor[T, K](
  source   : String,
  tokens   : Array[TokenInfo[T]],
  spec     : LanguageSpec[T, K],
  cursor   : ReuseCursor?,
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@green_tree.GreenNode, Array[Diagnostic], Int)  // Int = reuse_count
```

---

## Migration: Lambda Parser as Reference Implementation

The current `GreenParser` becomes `ParserContext`. The migration is mechanical:

**Before (current):**
```moonbit
fn GreenParser::parse_binary_op(self : GreenParser) -> Unit {
  let mark = self.mark_node()
  self.parse_application()
  // ...
  self.start_marked_node(mark, @syntax.BinaryExpr)
  self.emit_token(@syntax.PlusToken)
  self.finish_node()
}
```

**After (migrated):**
```moonbit
fn parse_binary_op(ctx : ParserContext[@token.Token, @syntax.SyntaxKind]) -> Unit {
  let mark = ctx.mark()
  parse_application(ctx)
  // ...
  ctx.start_at(mark, @syntax.BinaryExpr)
  ctx.emit_token(@syntax.PlusToken)
  ctx.finish_node()
}
```

The rename map: `self.mark_node()` → `ctx.mark()`, `self.start_marked_node(m, k)` → `ctx.start_at(m, k)`, `self.parse_X()` → `parse_X(ctx)`. All parse logic is identical.

**The Lambda `LanguageSpec`** (created once):
```moonbit
let lambda_spec : LanguageSpec[@token.Token, @syntax.SyntaxKind] = {
  kind_to_raw     : SyntaxKind::to_raw,
  token_is_eof    : fn(t) { t == @token.EOF },
  tokens_equal    : fn(a, b) { a == b },
  whitespace_kind : WhitespaceToken,
  eof_token       : @token.EOF,
}
```

---

## What a New Language Author Writes

Steps to define a new language parser, in order of effort:

| Step | What | Approx. lines |
|------|------|---------------|
| 1 | Define `Token` enum | ~15 |
| 2 | Define `SyntaxKind` enum with `to_raw`/`from_raw` | ~30 |
| 3 | Write `tokenize()` function | ~30–80 |
| 4 | Build `LanguageSpec` record | ~8 |
| 5 | Write grammar functions against `ParserContext` | varies |
| 6 | Call `parse_with(source, spec, tokenize, my_grammar)` | 1 |

Steps 1–4 are boilerplate. Step 5 looks exactly like `green_parser.mbt`.

---

## Phase 2: Combinator Layer (Additive, No Breaking Changes)

Thin wrappers over `ParserContext` — no closures stored, no heap allocation per parse, no changes to existing grammar code:

```moonbit
// combinators.mbt in parser-core
pub fn node[T, K](
  ctx  : ParserContext[T, K],
  kind : K,
  body : (ParserContext[T, K]) -> Unit,
) -> Unit {
  ctx.start_node(kind)
  body(ctx)
  ctx.finish_node()
}

pub fn repeat_while[T, K](
  ctx  : ParserContext[T, K],
  cond : (T) -> Bool,
  body : (ParserContext[T, K]) -> Unit,
) -> Unit {
  while cond(ctx.peek()) { body(ctx) }
}

pub fn choice[T, K](
  ctx  : ParserContext[T, K],
  alts : Array[(ParserContext[T, K]) -> Bool],
) -> Bool {
  for alt in alts {
    if alt(ctx) { return true }
  }
  false
}
```

For the arena/static memory scheme: combinator objects defined at module level (static) pay zero per-parse allocation. For dynamic combinator construction, a bump-allocator over WASM linear memory is the recommended approach.

---

## Key Design Decisions

- **`LanguageSpec` is a record, not a trait**: avoids associated-type limitations, equally type-safe, and the static record pattern means zero runtime overhead
- **`ParserContext` is the stable surface**: combinators in Phase 2 only call these 9 methods, so existing grammar functions require zero changes
- **Tokenizer is a function parameter, not part of `LanguageSpec`**: keeps tokenization orthogonal and allows pre-tokenized input (incremental path)
- **`green-tree/` stays language-agnostic**: no changes needed, it already uses `RawKind`
- **Lambda parser becomes the reference implementation**: proves the API is sufficient and gives new language authors a concrete model to follow
