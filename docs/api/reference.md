# Public API Reference

Lambda calculus parser — user-facing API for tokenizing, parsing, pretty printing, and error handling.

## 1. Parsing Functions

### `parse`

```moonbit
pub fn parse(String) -> Term raise
```

Parses an input string directly into a `Term` AST. Raises errors if tokenization fails or if the input contains syntax errors. The simplest entry point when only the semantic AST is needed.

### `parse_tree`

```moonbit
pub fn parse_tree(String) -> @ast.AstNode raise
```

Parses a string into an `AstNode` with position tracking. Routes through the CST internally. Use this when source positions (byte offsets) are required alongside the typed AST.

### `parse_cst`

```moonbit
pub fn parse_cst(String) -> @seam.CstNode raise
```

Parses a string into an immutable `CstNode` tree — a lossless CST with structural hashing. Raises on tokenization failure. All whitespace is preserved as trivia nodes.

### `parse_cst_recover`

```moonbit
pub fn parse_cst_recover(String) -> (@seam.CstNode, Array[Diagnostic]) raise
```

Like `parse_cst` but returns error nodes instead of raising, paired with a diagnostic list. Prefer this when the caller needs to continue despite syntax errors (e.g., editors, IDEs, incremental pipelines).

---

## 2. Tokenization

```moonbit
pub fn tokenize(String) -> Array[Token] raise @core.LexError
```

Converts an input string into an array of tokens. Raises `@core.LexError` if the input contains invalid characters.

**Example:**

```moonbit
let tokens = tokenize("λx.x + 1")
// [Lambda, Identifier("x"), Dot, Identifier("x"), Plus, Integer(1), EOF]
```

---

## 3. Pretty Printing

### `print_term`

```moonbit
pub fn print_term(Term) -> String
```

Converts a `Term` AST back into a human-readable string representation. May add extra parentheses for unambiguous output.

**Example:**

```moonbit
let ast = parse("λx.x + 1")
let output = print_term(ast)
// "(λx. (x + 1))"
```

### `print_token`

```moonbit
pub fn print_token(Token) -> String
```

Converts a single token to its string representation. Useful in error messages.

### `print_tokens`

```moonbit
pub fn print_tokens(Array[Token]) -> String
```

Converts an array of tokens to a bracketed, comma-separated string.

---

## 4. Error Types

### `@core.LexError`

Raised when the lexer encounters an invalid character or encoding issue.

```moonbit
pub(all) suberror LexError String  // defined in @core
```

**Example:**

```moonbit
try {
  let result = tokenize("@invalid")
} catch {
  @core.LexError(msg) => println("Lex error: " + msg)
}
```

### `ParseError`

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

---

## 5. CST Key Types

All CST types come from the `seam` package (`src/seam/`).

- **`CstNode`** — Immutable CST node: kind, children, text length, structural hash, token count. Position-independent; structurally shareable. `text_len`, `hash`, and `token_count` are cached at construction time.
- **`CstToken`** — Leaf token with kind, text, and cached structural hash.
- **`SyntaxNode`** — Ephemeral positioned view over a `CstNode`. Computes absolute byte offsets on demand via parent pointers; not stored persistently.
- **`RawKind`** — Language-agnostic node/token kind (a newtype over `Int`).

**Example:**

```moonbit
let cst = parse_cst("λx.x + 1")
let syntax = @seam.SyntaxNode::from_cst(cst)
// syntax.start() == 0, syntax.end() == 8

let ast = parse_tree("λx.x + 1")
// AstNode{ kind: Lam("x"), start: 0, end: 8, ... }

for child in syntax.children() {
  // child.start(), child.end(), child.kind()
}
```

---

## 6. Usage Examples

### Identity Function

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
