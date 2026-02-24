# Parser Module

A lexer and parser implementation for Lambda Calculus expressions with extensions for arithmetic operations and conditional expressions.

## Overview

This module provides a complete parsing pipeline for a Lambda Calculus-based language, transforming text input into an Abstract Syntax Tree (AST) representation. The implementation follows a traditional two-phase approach:

1. **Lexical Analysis (Lexer)**: Tokenizes input strings into a stream of tokens
2. **Syntactic Analysis (Parser)**: Parses token streams into typed AST terms

## Features

- **Lambda Calculus Core**: Variables, lambda abstractions, and function applications
- **Arithmetic Operations**: Binary operators (`+`, `-`)
- **Conditionals**: If-then-else expressions
- **Robust Error Handling**: Custom error types for tokenization and parsing failures
- **Pretty Printing**: Convert AST back to readable string representations

## Documentation

- [docs/README.md](docs/README.md) — Documentation index
- [docs/CORRECTNESS.md](docs/CORRECTNESS.md) — Correctness goals and verification
- [ROADMAP.md](ROADMAP.md) — Architecture and phased plan
- [docs/plans/2026-02-23-generic-parser-design.md](docs/plans/2026-02-23-generic-parser-design.md) — Generic parser framework design
- [docs/plans/2026-02-23-generic-parser-impl.md](docs/plans/2026-02-23-generic-parser-impl.md) — Generic parser framework implementation plan

## Benchmarks

Performance benchmarks measure incremental parsing efficiency:

```bash
# Full benchmark suite
moon bench --package dowdiness/parser/benchmarks --release

# Focused CST microbenchmarks
moon bench --package dowdiness/parser/benchmarks --file cst_benchmark.mbt --release
```

Key benchmarks:
- `incremental vs full - edit at start/end/middle` — Measures edit performance
- `worst case - full invalidation` — Edit that invalidates entire tree
- `best case - cosmetic change` — Localized edit with potential reuse
- `CST - token/node/equality` — Focused construction/hash/equality microbenchmarks

### Cursor Optimization

The `ReuseCursor` uses a stateful traversal (stack of frames) instead of
searching from root on every call, achieving O(depth) per lookup instead of
O(tree).

## Language Syntax

### Basic Elements

```
Integer    ::= [0-9]+
Identifier ::= [a-zA-Z][a-zA-Z0-9]*
Lambda     ::= λ | \
```

### Grammar

```
Expression  ::= BinaryOp

BinaryOp    ::= Application (('+' | '-') Application)*

Application ::= Atom Atom*

Atom        ::= Integer
              | Identifier
              | Lambda Identifier '.' Expression
              | 'if' Expression 'then' Expression 'else' Expression
              | '(' Expression ')'
```

### Operator Precedence (lowest to highest)

1. Binary operators (`+`, `-`) - left associative
2. Function application - left associative
3. Lambda abstraction - right associative

## Data Types

### Token

Represents lexical units in the input:

```moonbit
pub enum Token {
  Lambda        // λ or \
  Dot           // .
  LeftParen     // (
  RightParen    // )
  Plus          // +
  Minus         // -
  If            // if
  Then          // then
  Else          // else
  Identifier(String)  // variable names
  Integer(Int)        // integer literals
  EOF           // end of input
}
```

### Term

Represents parsed expressions as an AST:

```moonbit
pub enum Bop {
  Plus
  Minus
}

pub enum Term {
  Int(Int)                // Integer literal
  Var(VarName)           // Variable
  Lam(VarName, Term)     // Lambda abstraction
  App(Term, Term)        // Function application
  Bop(Bop, Term, Term)   // Binary operation
  If(Term, Term, Term)   // Conditional expression
}
```

## Public API

### Tokenization

```moonbit
pub fn tokenize(String) -> Array[Token] raise TokenizationError
```

Converts an input string into an array of tokens. Raises `TokenizationError` if the input contains invalid characters.

**Example:**
```moonbit
let tokens = tokenize("λx.x + 1")
// [Lambda, Identifier("x"), Dot, Identifier("x"), Plus, Integer(1), EOF]
```

### Parsing

```moonbit
pub fn parse(String) -> Term raise
```

Parses an input string directly into a Term AST. Raises errors if tokenization fails or if the input contains syntax errors.

**Example:**
```moonbit
let ast = parse("λx.x + 1")
// Lam("x", Bop(Plus, Var("x"), Int(1)))
```

### Concrete Syntax Tree (CST)

The parser produces a lossless Concrete Syntax Tree before converting to the semantic AST.

```moonbit
pub fn parse_cst(String) -> @seam.CstNode raise
```

Parses a string into an immutable `CstNode` tree (lossless CST with structural hashing).

```moonbit
pub fn parse_cst_recover(String) -> (@seam.CstNode, Array[Diagnostic]) raise
```

Like `parse_cst` but returns error nodes instead of raising, paired with a diagnostic list.

```moonbit
pub fn parse_tree(String) -> @ast.AstNode raise
```

Parses a string into an `AstNode` with position tracking. Routes through the CST internally.

**Key types (from `seam` package):**

- `CstNode` — Immutable CST node: kind, children, text length, structural hash, token count. Position-independent; structurally shareable.
- `CstToken` — Leaf token with kind, text, and cached structural hash.
- `SyntaxNode` — Ephemeral positioned view over a `CstNode`. Computes absolute byte offsets on demand via parent pointers; not stored persistently.
- `RawKind` — Language-agnostic node/token kind (a newtype over `Int`).

**Example:**
```moonbit
let cst = parse_cst("λx.x + 1")
let syntax = @seam.SyntaxNode::from_cst(cst)
// syntax.start() == 0, syntax.end() == 8
let ast = parse_tree("λx.x + 1")
// AstNode{ kind: Lam("x"), start: 0, end: 8, ... }
```

### Seam Module — CST Infrastructure (`src/seam/`)

The `seam` package implements a language-agnostic CST infrastructure modelled after [rowan](https://github.com/rust-analyzer/rowan) (the Rust library used by rust-analyzer). Understanding this model is required to work with `CstNode`, `SyntaxNode`, and the event stream.

#### Two-tree model

| `seam` type | rowan equivalent | Role |
|---|---|---|
| `RawKind` | `SyntaxKind` | Language-specific node/token kind, newtype over `Int` |
| `CstNode` | `GreenNode` | Immutable, position-independent, content-addressed CST node |
| `CstToken` | `GreenToken` | Immutable leaf token with kind and text |
| `SyntaxNode` | `SyntaxNode` | Ephemeral positioned view; adds absolute offsets |

**`CstNode`** stores structure and content but has no knowledge of where in the source file it appears. Its `hash` field is a structural content hash that enables efficient equality checks and structural sharing. Once constructed, `children` must not be mutated — `text_len`, `hash`, and `token_count` are cached at construction time.

**`SyntaxNode`** is a thin wrapper that adds a source offset. It is created on demand and walks the `CstNode` tree to compute child positions by accumulating text lengths.

#### Event stream → CST model

`CstNode` trees are not built directly. Instead, a parser emits a flat sequence of `ParseEvent`s into an `EventBuffer`, then `build_tree()` replays the buffer:

```moonbit
// Three event types drive tree construction:
StartNode(RawKind)   // push a new node frame
FinishNode           // pop frame, wrap children into a CstNode
Token(RawKind, String) // attach a leaf token to the current frame
```

A fourth event, `Tombstone`, enables **retroactive wrapping** — the parser can reserve a slot with `mark()` before it knows the node kind, then fill it with `start_at(mark, kind)` later:

```moonbit
// Binary expression "1 + 2" — the BinaryExpr wrapper is decided after
// both operands are parsed:
let buf = EventBuffer::new()
let m = buf.mark()               // reserve slot; buf contains [Tombstone]
buf.push(Token(IntLit, "1"))
buf.push(Token(Plus, "+"))
buf.push(Token(IntLit, "2"))
buf.start_at(m, BinaryExpr)     // retroactively fill: [StartNode(BinaryExpr), ...]
buf.push(FinishNode)
let cst = build_tree(buf.to_events(), SourceFile)
```

#### Traversal example

```moonbit
let cst = parse_cst("λx.x + 1")
let syntax = @seam.SyntaxNode::from_cst(cst)
inspect(syntax.start())  // 0
inspect(syntax.end())    // 8
for child in syntax.children() {
  // child.start(), child.end(), child.kind()
}
```

#### Non-goals

The `seam` module is deliberately language-agnostic. It does not know about lambda calculus, `SyntaxKind`, or any parser-specific concerns — those live in `src/parser/`. The only language-specific hook is `RawKind`, which each language maps to/from its own kind enum.

### Generic Parser Core (`src/core/`)

The `dowdiness/parser/core` package exposes a language-agnostic parsing infrastructure. Any MoonBit project can define a new parser by providing token and syntax-kind types — no need to reimplement the green tree, error recovery, or incremental subtree-reuse logic.

**Three types:**

```moonbit
// Generic token with source position.
pub struct TokenInfo[T] { token : T; start : Int; end : Int }

// Describes one language. Create once at module init, reuse across all parses.
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

// Core parser state — grammar functions receive this and call methods on it.
pub struct ParserContext[T, K] { ... }
```

**Methods grammar code uses:**

```moonbit
ctx.peek()                 // next non-trivia token
ctx.at(token)              // test current token
ctx.at_eof()               // test end of input
ctx.emit_token(kind)       // consume current token, emit as leaf
ctx.start_node(kind)       // open a node
ctx.finish_node()          // close the most recent node
ctx.mark()                 // reserve a retroactive-wrap position
ctx.start_at(mark, kind)   // wrap previously emitted children
ctx.error(msg)             // record a diagnostic (does not consume)
ctx.bump_error()           // consume current token as an error token
ctx.emit_error_placeholder() // zero-width error token (for missing tokens)
```

**Entry point:**

```moonbit
pub fn parse_with[T, K](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, Array[Diagnostic[T]])
```

The Lambda Calculus parser in `src/parser/` serves as the reference implementation (`lambda_spec.mbt`, `cst_parser.mbt`). See [docs/plans/2026-02-23-generic-parser-design.md](docs/plans/2026-02-23-generic-parser-design.md) for the full design.

### Pretty Printing

```moonbit
pub fn print_term(Term) -> String
```

Converts a Term AST back into a human-readable string representation.

**Example:**
```moonbit
let ast = parse("λx.x + 1")
let output = print_term(ast)
// "(λx. (x + 1))"
```

```moonbit
pub fn print_token(Token) -> String
```

Converts a single token to its string representation.

```moonbit
pub fn print_tokens(Array[Token]) -> String
```

Converts an array of tokens to a bracketed, comma-separated string.

## Usage Examples

### Simple Lambda Function

```moonbit
let identity = parse("λx.x")
print_term(identity)
// "(λx. x)"
```

### Function Application

```moonbit
let apply = parse("(λx.x) 42")
print_term(apply)
// "((λx. x) 42)"
```

### Arithmetic Operations

```moonbit
let arithmetic = parse("10 - 5 + 2")
print_term(arithmetic)
// "((10 - 5) + 2)"
```

### Conditional Expressions

```moonbit
let conditional = parse("if x then y else z")
print_term(conditional)
// "if x then y else z"
```

### Complex Nested Expression

```moonbit
let complex = parse("(λf.λx.if f x then x + 1 else x - 1)")
print_term(complex)
// "(λf. (λx. if (f x) then (x + 1) else (x - 1)))"
```

### Church Numerals

```moonbit
// Church encoding of number 2
let two = parse("λf.λx.f (f x)")
print_term(two)
// "(λf. (λx. (f (f x))))"
```

## Error Handling

The module provides two custom error types:

### TokenizationError

Raised when the lexer encounters an invalid character or encoding issue.

```moonbit
pub suberror TokenizationError String
```

**Example:**
```moonbit
try {
  let result = tokenize("@invalid")
} catch {
  TokenizationError(msg) => println("Tokenization failed: " + msg)
}
```

### ParseError

Raised when the parser encounters unexpected tokens or malformed syntax.

```moonbit
pub suberror ParseError (String, Token)
```

**Example:**
```moonbit
try {
  let result = parse("λ.x")  // Missing parameter name
} catch {
  ParseError((msg, token)) => {
    println("Parse error: " + msg)
    println("At token: " + print_token(token))
  }
}
```

## Implementation Details

### Parse Pipeline

The canonical parse pipeline is:

```
Source string → Lexer → EventBuffer → CstNode (CST) → SyntaxNode → AstNode → Term
```

1. **Lexer** tokenizes the source into a stream of typed tokens
2. **CST Parser** emits `ParseEvent`s into an `EventBuffer`; `build_tree()` constructs the immutable `CstNode` tree
3. **SyntaxNode** wraps the `CstNode` to add absolute byte positions on demand
4. **Conversion** walks `SyntaxNode` to produce `AstNode` (typed AST with positions)
5. **Simplification** converts `AstNode` to `Term` (semantic AST without positions)

### Lexer (`src/lexer/`)

The lexer performs character-by-character scanning with:
- **Whitespace handling**: Preserves whitespace as trivia tokens for lossless round-tripping
- **Keyword recognition**: Identifies reserved words (`if`, `then`, `else`)
- **Number parsing**: Reads multi-digit integers
- **Identifier reading**: Supports alphanumeric variable names
- **Unicode support**: Accepts both `λ` (U+03BB) and `\` for lambda

### CST Parser (`src/parser/cst_parser.mbt`)

Produces a lossless CST using an event buffer pattern:
- Grammar functions call `ctx.start_node(kind)` / `ctx.emit_token(kind)` / `ctx.finish_node()`
- `ctx.mark()` / `ctx.start_at(mark, kind)` enable retroactive wrapping (binary expressions, applications)
- `build_tree()` replays the flat `EventBuffer` to construct the immutable `CstNode` tree
- Preserves all whitespace as `WhitespaceToken` nodes for lossless round-tripping

### SyntaxNode (`src/seam/syntax_node.mbt`)

Ephemeral positioned view over a `CstNode`:
- Computes absolute byte offsets from the CST's cumulative text lengths
- Maintains parent pointers for upward traversal
- Created on demand; not stored persistently

### CST-to-AST Conversion (`src/parser/cst_convert.mbt`)

Converts the CST to typed `AstNode`s using `SyntaxNode` for position computation:
- `convert_syntax_node()` walks the `SyntaxNode` tree, using `syntax.children()` for correct offsets
- `tight_span()` computes precise positions by skipping leading/trailing whitespace tokens
- `ParenExpr` nodes are unwrapped to their inner expression's kind in the AST

### Pretty Printer (`src/ast/`)

The `print_term` function traverses the AST and reconstructs expressions with:
- Parentheses for clarity (may add extra parens for unambiguous output)
- Lambda notation using `λ` character
- Infix notation for binary operations
- Natural formatting for conditionals

## Testing

The module includes comprehensive tests ([parser_test.mbt](parser_test.mbt)) covering:

- **Basic parsing**: Integers, variables, simple lambdas
- **Complex expressions**: Nested lambdas, multiple applications, mixed operators
- **Error cases**: Missing tokens, unmatched parentheses, malformed syntax
- **Edge cases**: Single characters, large numbers, operator chains
- **Integration**: Complete expressions using all language features

Run tests with:
```bash
moon test --package parser

# Fast differential checks (CI-friendly per-PR)
moon test --package parser --filter '*differential-fast*'

# Longer deterministic differential fuzz pass (nightly/local)
moon test --package parser --filter '*differential-long*'
```

## Relation to CRDT

While this parser module is currently a standalone Lambda Calculus parser, it can serve as a foundation for future CST (Concrete Syntax Tree) integration with the CRDT module. The AST representation in this module demonstrates how tree-structured data can be represented and manipulated, which aligns with the planned CST support for the CRDT implementation.

Potential integration points:
- The `Term` enum could be adapted as a CST node representation
- The parser could generate CRDT operations for incremental parsing
- The AST could be stored in a CRDT TreeDocument for collaborative editing

## References

- **Lambda Calculus**: Church's λ-calculus formal system for computation
- **Recursive Descent Parsing**: Top-down parsing technique used in implementation
- **Abstract Syntax Trees**: Tree representation of program structure

## Future Enhancements

Possible extensions for the parser:

1. **Type System**: Add type annotations and type checking
2. **More Operators**: Multiplication, division, comparison operators
3. **Let Bindings**: Local variable definitions
4. **Pattern Matching**: Advanced lambda parameter patterns
5. **Source Locations**: Track line/column information for better error messages
6. **Semantics-Aware Reuse**: Follow-set checks for projectional/live editing contexts
