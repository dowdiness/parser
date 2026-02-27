# Lambda Calculus Language Reference

A description of the language syntax, grammar, operator precedence, and core data types for the Lambda Calculus parser.

## Basic Elements

```
Integer    ::= [0-9]+
Identifier ::= [a-zA-Z][a-zA-Z0-9]*
Lambda     ::= λ | \
```

Both `λ` (U+03BB) and `\` are accepted as the lambda symbol.

## Grammar

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

The grammar is right-recursive for lambda abstraction (`λx.body` extends as far right as possible) and left-recursive for application and binary operations (handled iteratively in the recursive-descent parser).

## Operator Precedence (lowest to highest)

1. Binary operators (`+`, `-`) — left associative
2. Function application — left associative
3. Lambda abstraction — right associative (body extends to end of expression)

## Data Types

### Token

`Token` represents lexical units produced by the lexer from source text:

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

`Term` represents parsed expressions as a semantic AST. Position information is not stored here — it lives in `AstNode` at the CST layer.

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

`VarName` is an alias for `String` used to distinguish variable names from other strings.

## Examples

| Source text | `Term` representation |
|---|---|
| `λx.x` | `Lam("x", Var("x"))` |
| `1 + 2` | `Bop(Plus, Int(1), Int(2))` |
| `f x` | `App(Var("f"), Var("x"))` |
| `if x then y else z` | `If(Var("x"), Var("y"), Var("z"))` |
| `λf.λx.f (f x)` | `Lam("f", Lam("x", App(Var("f"), App(Var("f"), Var("x")))))` |

## Error Types

### TokenizationError

Raised when the lexer encounters an invalid character or encoding issue.

```moonbit
pub suberror TokenizationError String
```

### ParseError

Raised when the parser encounters unexpected tokens or malformed syntax.

```moonbit
pub suberror ParseError (String, Token)
```

The tuple carries a human-readable message and the offending token.
