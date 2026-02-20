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

## Benchmarks

Performance benchmarks measure incremental parsing efficiency:

```bash
# Full benchmark suite
moon bench --package dowdiness/parser/benchmarks --release

# Focused green-tree microbenchmarks
moon bench --package dowdiness/parser/benchmarks --file green_tree_benchmark.mbt --release
```

Key benchmarks:
- `incremental vs full - edit at start/end/middle` — Measures edit performance
- `worst case - full invalidation` — Edit that invalidates entire tree
- `best case - cosmetic change` — Localized edit with potential reuse
- `green-tree - token/node/equality` — Focused construction/hash/equality microbenchmarks

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

The parser produces a lossless Concrete Syntax Tree using a green/red tree architecture before converting to the semantic AST.

```moonbit
pub fn parse_green(String) -> GreenNode raise
```

Parses a string into an immutable green tree (CST). Green nodes store relative widths, enabling structural sharing.

```moonbit
pub fn parse_tree(String) -> TermNode raise
```

Parses a string into a `TermNode` with position tracking. Routes through the green tree internally: `parse_green` -> `green_to_term_node`.

```moonbit
pub fn green_to_term_node(GreenNode, Int, Ref[Int]) -> TermNode
```

Converts a `GreenNode` to a `TermNode`. The `Int` parameter is the byte offset, and `Ref[Int]` is a node ID counter. Internally wraps the green node in a `RedNode` for position computation.

```moonbit
pub fn red_to_term_node(RedNode, Ref[Int]) -> TermNode
```

Converts a `RedNode` (position-aware CST facade) directly to a `TermNode`.

**Key types:**

- `GreenNode` -- Immutable CST node storing kind, children, and text width. Position-independent.
- `GreenToken` -- Leaf token in the green tree with kind and text.
- `RedNode` -- Ephemeral wrapper around `GreenNode` that computes absolute byte positions on demand via parent pointers.

Hashing notes:
- `GreenToken`/`GreenNode` store a cached structural hash computed during construction (FNV utility).
- `Hash` trait impls reuse cached hashes for `HashMap`/`HashSet` interoperability.

**Example:**
```moonbit
let green = parse_green("λx.x + 1")
let red = RedNode::from_green(green)
let term_node = red_to_term_node(red, Ref::new(0))
```

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
Source string -> Lexer -> Green Tree (CST) -> Red Tree -> TermNode -> Term
```

1. **Lexer** tokenizes the source into a stream of tokens
2. **Green Parser** produces an immutable green tree (lossless CST with relative widths)
3. **Red Tree** wraps the green tree to compute absolute byte positions on demand
4. **Conversion** transforms the red tree into `TermNode` (typed AST with positions)
5. **Simplification** converts `TermNode` to `Term` (semantic AST without positions)

### Lexer ([lexer.mbt](lexer.mbt))

The lexer performs character-by-character scanning with:
- **Whitespace handling**: Automatically skips spaces, tabs, and newlines
- **Keyword recognition**: Identifies reserved words (`if`, `then`, `else`)
- **Number parsing**: Reads multi-digit integers
- **Identifier reading**: Supports alphanumeric variable names
- **Unicode support**: Accepts both `λ` (U+03BB) and `\` for lambda

### Green Parser ([green_parser.mbt](green_parser.mbt))

Produces a lossless Concrete Syntax Tree using an event buffer pattern:
- Emits `ParseEvent`s (StartNode, FinishNode, Token) into a flat buffer
- Uses `mark()`/`start_at()` for retroactive wrapping (binary expressions, applications)
- `build_tree()` replays events to construct the immutable `GreenNode` tree
- Preserves all whitespace as `WhitespaceToken` nodes for lossless round-tripping

### Red Tree ([red_tree.mbt](red_tree.mbt))

Ephemeral facade over the green tree for position queries:
- Computes absolute byte offsets from the green tree's relative widths
- Maintains parent pointers for upward traversal
- Created on demand, not stored persistently

### Green-to-AST Conversion ([green_convert.mbt](green_convert.mbt))

Converts the CST to typed AST nodes using `RedNode` for position computation:
- `convert_red()` walks the red tree, using `red.children()` for child iteration with correct offsets
- `tight_span()` computes precise positions by skipping leading/trailing whitespace
- `ParenExpr` nodes are unwrapped to their inner expression's kind in the AST

### Parser ([parser.mbt](parser.mbt))

The `parse_tree` function routes through the green tree as the canonical path. A legacy `parse_tree_from_tokens` function provides direct recursive descent for the `IncrementalParser` token-based path.

### Pretty Printer ([term.mbt](term.mbt))

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
