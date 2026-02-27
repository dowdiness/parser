# `dowdiness/parser/lambda`

Concrete lambda calculus implementation of the generic parser infrastructure.
Two responsibilities: **incremental pipeline** and **graphviz visualization**.

## Public API

```moonbit
// ── Pipeline ──────────────────────────────────────────────────────────────────

pub struct LambdaLanguage {}
pub impl @pipeline.Parseable for LambdaLanguage

pub fn lambda_language() -> @pipeline.Language[@ast.AstNode]

pub struct LambdaParserDb { /* private */ }
pub fn LambdaParserDb::new(String)            -> Self
pub fn LambdaParserDb::set_source(Self, String) -> Unit
pub fn LambdaParserDb::cst(Self)              -> @pipeline.CstStage
pub fn LambdaParserDb::diagnostics(Self)      -> Array[String]
pub fn LambdaParserDb::term(Self)             -> @ast.AstNode

// ── Visualization ─────────────────────────────────────────────────────────────

pub fn to_dot(@ast.AstNode) -> String
```

## Pipeline

`LambdaLanguage` implements `@pipeline.Parseable` — the single method
`parse_source(String) -> CstStage` combines tokenize + parse into one call,
erasing `@token.Token` from callers.

`lambda_language()` wraps a `LambdaLanguage` into a `Language[AstNode]`
vtable (token-erased dictionary), passing `to_ast` and `on_lex_error` closures.

`LambdaParserDb` is a convenience wrapper over `@pipeline.ParserDb[AstNode]`,
exposing the same `new / set_source / cst / diagnostics / term` API with a
concrete `AstNode` type so callers don't need to write the type parameter.

```moonbit
let db = LambdaParserDb::new("λx.x + 1")
db.set_source("λx.x + 2")
let node = LambdaParserDb::term(db)  // @ast.AstNode
```

## Visualization

`to_dot` converts an `AstNode` tree to a Graphviz DOT string by delegating
to `@viz.to_dot[DotAstNode]`.

### Orphan rule — why `DotAstNode` exists

MoonBit requires that you own either the trait or the type to implement it.
`@viz.DotNode` is foreign (defined in `viz`) and `@ast.AstNode` is foreign
(defined in `ast`), so `lambda` cannot implement `DotNode for AstNode` directly.

The fix: define a private newtype wrapper in this package:

```moonbit
priv struct DotAstNode { node : @ast.AstNode }
impl @viz.DotNode for DotAstNode with ...
```

`DotAstNode` is local, so the impl is legal. `to_dot` wraps and unwraps
transparently — callers always work with plain `@ast.AstNode`.

The same pattern applies whenever you need to bridge two foreign packages.
See `src/viz/README.md` for the `DotNode` trait contract.
