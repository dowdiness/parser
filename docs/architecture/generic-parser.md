# Generic Parser Core (src/core/)

The `dowdiness/parser/core` package exposes a language-agnostic parsing infrastructure. Any MoonBit project can define a new parser by providing token and syntax-kind types — no need to reimplement the CST, error recovery, or incremental subtree-reuse logic.

## Three Core Types

### TokenInfo

A generic token with source position:

```moonbit
pub struct TokenInfo[T] {
  token : T
  start : Int
  end   : Int
}
```

`T` is the language-specific token type. The lexer produces `Array[TokenInfo[T]]`; the parser consumes it through `ParserContext`.

### LanguageSpec

Describes one language. Create once at module initialisation, reuse across all parses:

```moonbit
pub struct LanguageSpec[T, K] {
  kind_to_raw     : (K) -> RawKind
  token_is_eof    : (T) -> Bool
  token_is_trivia : (T) -> Bool
  tokens_equal    : (T, T) -> Bool
  print_token     : (T) -> String
  whitespace_kind : K
  error_kind      : K
  root_kind       : K
  eof_token       : T
}
```

- `T` — language-specific token type (e.g. `Token` from `src/examples/lambda/token/`)
- `K` — language-specific syntax kind type (e.g. `SyntaxKind` from `src/examples/lambda/syntax/`)
- `kind_to_raw` — maps the language kind to the `RawKind` integer used by `seam`
- `token_is_trivia` — identifies whitespace and comments, which the parser skips by default
- `whitespace_kind`, `error_kind`, `root_kind` — fixed kinds used for trivia nodes, error recovery, and the implicit root wrapper

### ParserContext

Core parser state. Grammar functions receive a `ParserContext` and call methods on it to build the CST event stream:

```moonbit
pub struct ParserContext[T, K] { ... }
```

The internal fields are not part of the public API. All interaction is through the methods listed below.

## Grammar API

Methods that grammar functions call on `ParserContext`:

```moonbit
ctx.peek()                   // next non-trivia token (does not consume)
ctx.at(token)                // test whether current token equals the given token
ctx.at_eof()                 // test whether all input has been consumed
ctx.emit_token(kind)         // consume current token, emit it as a leaf with the given kind
ctx.start_node(kind)         // open a new node frame with the given kind
ctx.finish_node()            // close the most recently opened node frame
ctx.mark()                   // reserve a retroactive-wrap position (returns a Mark)
ctx.start_at(mark, kind)     // retroactively wrap children emitted since mark
ctx.error(msg)               // record a diagnostic without consuming a token
ctx.bump_error()             // consume current token as an error token
ctx.emit_error_placeholder() // emit a zero-width error token (for missing tokens)
```

`mark()` / `start_at()` implement the tombstone pattern described in [seam-model.md](seam-model.md). They are essential for left-associative constructs where the outer node kind is not known until after the first child is parsed.

## Entry Point

```moonbit
pub fn parse_with[T, K](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, Array[Diagnostic[T]])
```

`parse_with` drives the complete parse:

1. Calls `tokenize(source)` to produce the token array.
2. Constructs a `ParserContext` from the token array and `spec`.
3. Calls `grammar(ctx)` to run the language-specific grammar, which emits events into the context's internal `EventBuffer`.
4. Calls `build_tree()` on the buffer to produce the immutable `CstNode` tree.
5. Returns the tree paired with any diagnostics accumulated during parsing.

Error recovery is left to the grammar function. The framework provides `bump_error()` and `emit_error_placeholder()` as primitives; the grammar decides when and how to use them.

## Reference Implementation

The Lambda Calculus parser in `src/examples/lambda/` is the reference implementation:

- `lambda_spec.mbt` — defines the `LanguageSpec` for lambda calculus
- `cst_parser.mbt` — implements the grammar functions that call into `ParserContext`

See [docs/plans/2026-02-23-generic-parser-design.md](../plans/2026-02-23-generic-parser-design.md) for the full design rationale and [docs/plans/2026-02-23-generic-parser-impl.md](../plans/2026-02-23-generic-parser-impl.md) for the implementation plan.
