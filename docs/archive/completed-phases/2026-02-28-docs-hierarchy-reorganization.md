# Docs Hierarchy Reorganization

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reorganize documentation into an AI-agent-friendly hierarchy where top-level docs are succinct navigation aids and all detail lives in purpose-specific sub-documents.

**Architecture:** Three-tier structure — root (overview + links), `docs/` (navigation index + topic subfolders), `docs/archive/` (historical + completed-phase detail). No content is deleted; everything is moved or extracted.

**Principle:** Each document has one job. An agent reading any file should be able to find exactly what it needs in one more hop.

---

## Target Structure

```
README.md                        ~60 lines — overview, module map, links
ROADMAP.md                       ~350 lines — status table, arch diagram, future phases
docs/
  README.md                      ~50 lines — navigation index (rewritten)
  architecture/
    overview.md                  arch diagram + principles (extracted from ROADMAP §Target Architecture)
    language.md                  grammar, syntax, operator precedence (extracted from README)
    seam-model.md                two-tree CST model (extracted from README §Seam Module)
    generic-parser.md            LanguageSpec, ParserContext API (extracted from README §Generic Parser Core)
    pipeline.md                  parse pipeline detail (extracted from README §Implementation Details)
  api/
    reference.md                 public API + examples + error types (extracted from README)
    api-contract.md              (moved from docs/)
    pipeline-api-contract.md     (moved from docs/)
  correctness/
    CORRECTNESS.md               (moved from docs/)
    STRUCTURAL_VALIDATION.md     (moved from docs/)
    EDGE_CASE_TESTS.md           (moved from docs/)
  performance/
    PERFORMANCE_ANALYSIS.md      (moved from docs/)
    benchmark_history.md         (moved from docs/)
  decisions/                     (unchanged)
  plans/                         active only: node-interner*, syntax-node*
  archive/
    (existing 4 files, unchanged)
    completed-phases/
      phases-0-4.md              phase detail extracted from ROADMAP §Phase 0-4
      (12 completed phase plan files moved here from docs/plans/)
    LEZER_IMPLEMENTATION.md      (moved from docs/)
    LEZER_FRAGMENT_REUSE.md      (moved from docs/)
    green-tree-extraction.md     (moved from docs/)
```

**Active plans to keep in docs/plans/ (future work, not complete):**
- `2026-02-25-node-interner-design.md`
- `2026-02-25-node-interner.md`
- `2026-02-25-syntax-node-extend.md`
- `2026-02-25-syntax-node-first-layer-design.md`

**Completed phase plans to archive (move to docs/archive/completed-phases/):**
- `2026-02-19-green-tree-extraction-design.md`
- `2026-02-19-green-tree-extraction.md`
- `2026-02-22-green-tree-publish-ready.md`
- `2026-02-22-incr-green-tree-integration-draft.md`
- `2026-02-23-generic-parser-design.md`
- `2026-02-23-generic-parser-impl.md`
- `2026-02-23-green-tree-token-interning-design.md`
- `2026-02-23-green-tree-token-interning.md`
- `2026-02-23-trivia-inclusive-lexer.md`
- `2026-02-24-generic-incremental-reuse-design.md`
- `2026-02-25-incr-parser-db.md`
- `2026-02-25-language-agnostic-pipeline.md`
- `2026-02-25-syntax-node-first-layer.md`
- `2026-02-27-merge-edit-range-into-core-design.md`
- `2026-02-27-merge-edit-range-into-core.md`

---

### Task 1: Create directory structure

**Files:**
- Create: `docs/architecture/` (directory)
- Create: `docs/api/` (directory)
- Create: `docs/correctness/` (directory)
- Create: `docs/performance/` (directory)
- Create: `docs/archive/completed-phases/` (directory)

**Step 1: Create all directories**

```bash
mkdir -p /home/antisatori/ghq/github.com/dowdiness/crdt/parser/docs/architecture
mkdir -p /home/antisatori/ghq/github.com/dowdiness/crdt/parser/docs/api
mkdir -p /home/antisatori/ghq/github.com/dowdiness/crdt/parser/docs/correctness
mkdir -p /home/antisatori/ghq/github.com/dowdiness/crdt/parser/docs/performance
mkdir -p /home/antisatori/ghq/github.com/dowdiness/crdt/parser/docs/archive/completed-phases
```

**Step 2: Verify**

```bash
ls /home/antisatori/ghq/github.com/dowdiness/crdt/parser/docs/
```

Expected: `architecture/  api/  correctness/  performance/  archive/  decisions/  plans/  README.md  ...`

**Step 3: Commit**

```bash
git add -A
git commit -m "chore(docs): create hierarchical directory structure"
```

---

### Task 2: Move existing docs into hierarchy (git mv)

**Files to move:**

| From | To |
|------|----|
| `docs/api-contract.md` | `docs/api/api-contract.md` |
| `docs/pipeline-api-contract.md` | `docs/api/pipeline-api-contract.md` |
| `docs/CORRECTNESS.md` | `docs/correctness/CORRECTNESS.md` |
| `docs/STRUCTURAL_VALIDATION.md` | `docs/correctness/STRUCTURAL_VALIDATION.md` |
| `docs/EDGE_CASE_TESTS.md` | `docs/correctness/EDGE_CASE_TESTS.md` |
| `docs/PERFORMANCE_ANALYSIS.md` | `docs/performance/PERFORMANCE_ANALYSIS.md` |
| `docs/benchmark_history.md` | `docs/performance/benchmark_history.md` |
| `docs/LEZER_IMPLEMENTATION.md` | `docs/archive/LEZER_IMPLEMENTATION.md` |
| `docs/LEZER_FRAGMENT_REUSE.md` | `docs/archive/LEZER_FRAGMENT_REUSE.md` |
| `docs/green-tree-extraction.md` | `docs/archive/green-tree-extraction.md` |

**Step 1: git mv all files**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git mv docs/api-contract.md docs/api/api-contract.md
git mv docs/pipeline-api-contract.md docs/api/pipeline-api-contract.md
git mv docs/CORRECTNESS.md docs/correctness/CORRECTNESS.md
git mv docs/STRUCTURAL_VALIDATION.md docs/correctness/STRUCTURAL_VALIDATION.md
git mv docs/EDGE_CASE_TESTS.md docs/correctness/EDGE_CASE_TESTS.md
git mv docs/PERFORMANCE_ANALYSIS.md docs/performance/PERFORMANCE_ANALYSIS.md
git mv docs/benchmark_history.md docs/performance/benchmark_history.md
git mv docs/LEZER_IMPLEMENTATION.md docs/archive/LEZER_IMPLEMENTATION.md
git mv docs/LEZER_FRAGMENT_REUSE.md docs/archive/LEZER_FRAGMENT_REUSE.md
git mv docs/green-tree-extraction.md docs/archive/green-tree-extraction.md
```

**Step 2: Commit**

```bash
git add -A
git commit -m "chore(docs): move existing docs into topic subdirectories"
```

---

### Task 3: Archive completed phase plans

Move all 15 completed-phase plan files from `docs/plans/` to `docs/archive/completed-phases/`.

**Step 1: git mv all completed plans**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/parser
git mv docs/plans/2026-02-19-green-tree-extraction-design.md docs/archive/completed-phases/
git mv docs/plans/2026-02-19-green-tree-extraction.md docs/archive/completed-phases/
git mv docs/plans/2026-02-22-green-tree-publish-ready.md docs/archive/completed-phases/
git mv docs/plans/2026-02-22-incr-green-tree-integration-draft.md docs/archive/completed-phases/
git mv docs/plans/2026-02-23-generic-parser-design.md docs/archive/completed-phases/
git mv docs/plans/2026-02-23-generic-parser-impl.md docs/archive/completed-phases/
git mv docs/plans/2026-02-23-green-tree-token-interning-design.md docs/archive/completed-phases/
git mv docs/plans/2026-02-23-green-tree-token-interning.md docs/archive/completed-phases/
git mv docs/plans/2026-02-23-trivia-inclusive-lexer.md docs/archive/completed-phases/
git mv docs/plans/2026-02-24-generic-incremental-reuse-design.md docs/archive/completed-phases/
git mv docs/plans/2026-02-25-incr-parser-db.md docs/archive/completed-phases/
git mv docs/plans/2026-02-25-language-agnostic-pipeline.md docs/archive/completed-phases/
git mv docs/plans/2026-02-25-syntax-node-first-layer.md docs/archive/completed-phases/
git mv docs/plans/2026-02-27-merge-edit-range-into-core-design.md docs/archive/completed-phases/
git mv docs/plans/2026-02-27-merge-edit-range-into-core.md docs/archive/completed-phases/
```

**Step 2: Verify docs/plans/ only has active future work**

```bash
ls /home/antisatori/ghq/github.com/dowdiness/crdt/parser/docs/plans/
```

Expected (4 active plans + this plan):
```
2026-02-25-node-interner-design.md
2026-02-25-node-interner.md
2026-02-25-syntax-node-extend.md
2026-02-25-syntax-node-first-layer-design.md
2026-02-28-docs-hierarchy-reorganization.md
```

**Step 3: Commit**

```bash
git add -A
git commit -m "chore(docs): archive completed phase plans"
```

---

### Task 4: Create docs/architecture/ docs (extracted from README.md)

Create four new files from content currently embedded in README.md.

**Files:**
- Create: `docs/architecture/language.md`
- Create: `docs/architecture/seam-model.md`
- Create: `docs/architecture/generic-parser.md`
- Create: `docs/architecture/pipeline.md`

**Step 1: Create docs/architecture/language.md**

Extract README.md §Language Syntax (lines ~52-83). Content:

```markdown
# Lambda Calculus Language Reference

## Basic Elements

\```
Integer    ::= [0-9]+
Identifier ::= [a-zA-Z][a-zA-Z0-9]*
Lambda     ::= λ | \
\```

## Grammar

\```
Expression  ::= BinaryOp

BinaryOp    ::= Application (('+' | '-') Application)*

Application ::= Atom Atom*

Atom        ::= Integer
              | Identifier
              | Lambda Identifier '.' Expression
              | 'if' Expression 'then' Expression 'else' Expression
              | '(' Expression ')'
\```

## Operator Precedence (lowest to highest)

1. Binary operators (`+`, `-`) — left associative
2. Function application — left associative
3. Lambda abstraction — right associative

## Data Types

### Token

\```moonbit
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
\```

### Term

\```moonbit
pub enum Bop { Plus; Minus }

pub enum Term {
  Int(Int)              // Integer literal
  Var(VarName)          // Variable
  Lam(VarName, Term)    // Lambda abstraction
  App(Term, Term)       // Function application
  Bop(Bop, Term, Term)  // Binary operation
  If(Term, Term, Term)  // Conditional expression
}
\```
```

**Step 2: Create docs/architecture/seam-model.md**

Extract README.md §Seam Module (lines ~195-252). Content:

```markdown
# Seam Module — CST Infrastructure

The `seam` package is a language-agnostic CST infrastructure modelled after
[rowan](https://github.com/rust-analyzer/rowan) (used by rust-analyzer).

## Two-Tree Model

| `seam` type | rowan equivalent | Role |
|---|---|---|
| `RawKind` | `SyntaxKind` | Language-specific node/token kind, newtype over `Int` |
| `CstNode` | `GreenNode` | Immutable, position-independent, content-addressed CST node |
| `CstToken` | `GreenToken` | Immutable leaf token with kind and text |
| `SyntaxNode` | `SyntaxNode` | Ephemeral positioned view; adds absolute offsets |

**`CstNode`** stores structure and content but has no knowledge of where in the
source it appears. Its `hash` field is a structural content hash enabling
efficient equality checks and structural sharing. `text_len`, `hash`, and
`token_count` are cached at construction time.

**`SyntaxNode`** is a thin wrapper that adds a source offset, created on demand
by walking the `CstNode` tree to compute child positions via accumulated text
lengths.

## Event Stream → CST

Trees are not built directly. A parser emits flat `ParseEvent`s into an
`EventBuffer`, then `build_tree()` replays the buffer:

\```moonbit
StartNode(RawKind)      // push a new node frame
FinishNode              // pop frame, wrap children into a CstNode
Token(RawKind, String)  // attach a leaf token to the current frame
\```

`Tombstone` enables retroactive wrapping — reserve a slot with `mark()` before
knowing the node kind, fill with `start_at(mark, kind)` later:

\```moonbit
// "1 + 2" — BinaryExpr wrapper decided after both operands are parsed:
let buf = EventBuffer::new()
let m = buf.mark()
buf.push(Token(IntLit, "1"))
buf.push(Token(Plus, "+"))
buf.push(Token(IntLit, "2"))
buf.start_at(m, BinaryExpr)
buf.push(FinishNode)
let cst = build_tree(buf.to_events(), SourceFile)
\```

## Non-Goals

`seam` is language-agnostic — it does not know about lambda calculus,
`SyntaxKind`, or parser-specific concerns. The only hook is `RawKind`.
```

**Step 3: Create docs/architecture/generic-parser.md**

Extract README.md §Generic Parser Core (lines ~254-308). Content:

```markdown
# Generic Parser Core (`src/core/`)

Any MoonBit project can define a new parser by providing token and syntax-kind
types — no need to reimplement CST, error recovery, or incremental reuse.

## Three Types

\```moonbit
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

// Core parser state — grammar functions receive this.
pub struct ParserContext[T, K] { ... }
\```

## Grammar API

\```moonbit
ctx.peek()                    // next non-trivia token
ctx.at(token)                 // test current token
ctx.at_eof()                  // test end of input
ctx.emit_token(kind)          // consume current token, emit as leaf
ctx.start_node(kind)          // open a node
ctx.finish_node()             // close the most recent node
ctx.mark()                    // reserve a retroactive-wrap position
ctx.start_at(mark, kind)      // wrap previously emitted children
ctx.error(msg)                // record a diagnostic (does not consume)
ctx.bump_error()              // consume current token as an error token
ctx.emit_error_placeholder()  // zero-width error token (for missing tokens)
\```

## Entry Point

\```moonbit
pub fn parse_with[T, K](
  source   : String,
  spec     : LanguageSpec[T, K],
  tokenize : (String) -> Array[TokenInfo[T]],
  grammar  : (ParserContext[T, K]) -> Unit,
) -> (@seam.CstNode, Array[Diagnostic[T]])
\```

The Lambda Calculus parser in `src/parser/` is the reference implementation
(`lambda_spec.mbt`, `cst_parser.mbt`).
```

**Step 4: Create docs/architecture/pipeline.md**

Extract README.md §Implementation Details (lines ~429-483) + §Parse Pipeline. Content:

```markdown
# Parse Pipeline

## Canonical Pipeline

\```
Source string → Lexer → EventBuffer → CstNode (CST) → SyntaxNode → AstNode → Term
\```

1. **Lexer** (`src/lexer/`) tokenizes source into typed tokens including whitespace trivia
2. **CST Parser** (`src/parser/cst_parser.mbt`) emits `ParseEvent`s; `build_tree()` constructs the immutable `CstNode`
3. **SyntaxNode** wraps `CstNode` to add absolute byte positions on demand
4. **Conversion** (`src/parser/cst_convert.mbt`) walks `SyntaxNode` → `AstNode` (typed, positioned)
5. **Simplification** converts `AstNode` → `Term` (semantic AST, no positions)

## Incremental Pipeline

\```
Edit { start, old_len, new_len }
  ↓
TokenBuffer::update()   re-lex only damaged region; splice into existing tokens
  ↓
IncrementalParser       damage tracking → ReuseCursor → parse only damaged subtrees
  ↓
ParserDb (reactive)     Signal[String] → Memo[CstStage] → Memo[AstNode]
\```

## Key Implementation Notes

**Lexer** (`src/lexer/`)
- Whitespace preserved as trivia tokens (lossless round-tripping)
- `TokenBuffer` uses splice-based re-lex: finds dirty token span, re-lexes only that region, splices result into existing buffer

**CST Parser** (`src/parser/cst_parser.mbt`)
- `ctx.mark()` / `ctx.start_at(mark, kind)` enable retroactive wrapping for binary expressions and application chains

**CST-to-AST Conversion** (`src/parser/cst_convert.mbt`)
- `tight_span()` computes precise positions by skipping leading/trailing whitespace
- `ParenExpr` nodes are unwrapped to their inner expression's kind

**ReuseCursor** (`src/core/`)
- Stateful traversal (stack of frames) — O(depth) per lookup vs O(tree) naive search
- 4-condition reuse protocol: kind match + leading context + trailing context + no damage overlap
```

**Step 5: Commit**

```bash
git add docs/architecture/
git commit -m "docs(architecture): extract language, seam, generic-parser, pipeline from README"
```

---

### Task 5: Create docs/api/reference.md (extracted from README.md)

Extract README.md §Public API + §Usage Examples + §Error Handling + §Pretty Printing.

**Files:**
- Create: `docs/api/reference.md`

**Step 1: Create docs/api/reference.md**

```markdown
# Public API Reference

## Parsing Functions

\```moonbit
// Parse source string to semantic AST (Term).
pub fn parse(String) -> Term raise

// Parse source string to typed AST with positions.
pub fn parse_tree(String) -> @ast.AstNode raise

// Parse source string to lossless CST.
pub fn parse_cst(String) -> @seam.CstNode raise

// Like parse_cst but returns error nodes instead of raising.
pub fn parse_cst_recover(String) -> (@seam.CstNode, Array[Diagnostic]) raise
\```

## Tokenization

\```moonbit
pub fn tokenize(String) -> Array[Token] raise TokenizationError
\```

Converts a string into an array of tokens including whitespace trivia.

**Example:**
\```moonbit
let tokens = tokenize("λx.x + 1")
// [Lambda, Identifier("x"), Dot, Identifier("x"), Plus, Integer(1), EOF]
\```

## Pretty Printing

\```moonbit
pub fn print_term(Term) -> String       // Term → readable string
pub fn print_token(Token) -> String     // single token → string
pub fn print_tokens(Array[Token]) -> String  // tokens → bracketed list
\```

**Example:**
\```moonbit
let ast = parse("λx.x + 1")
print_term(ast)
// "(λx. (x + 1))"
\```

## Error Types

\```moonbit
pub suberror TokenizationError String
pub suberror ParseError (String, Token)
\```

**Handling errors:**
\```moonbit
try {
  let result = parse("λ.x")  // Missing parameter name
} catch {
  ParseError((msg, token)) => println("Parse error: " + msg)
  TokenizationError(msg)    => println("Tokenization failed: " + msg)
}
\```

## CST Key Types

- `CstNode` — Immutable, position-independent, content-addressed CST node
- `CstToken` — Immutable leaf token with kind, text, structural hash
- `SyntaxNode` — Ephemeral positioned view (absolute offsets computed on demand)
- `RawKind` — Language-agnostic node/token kind (newtype over `Int`)

**Example:**
\```moonbit
let cst = parse_cst("λx.x + 1")
let syntax = @seam.SyntaxNode::from_cst(cst)
// syntax.start() == 0, syntax.end() == 8
\```

## Usage Examples

\```moonbit
// Identity function
print_term(parse("λx.x"))
// "(λx. x)"

// Application
print_term(parse("(λx.x) 42"))
// "((λx. x) 42)"

// Arithmetic
print_term(parse("10 - 5 + 2"))
// "((10 - 5) + 2)"

// Conditional
print_term(parse("if x then y else z"))
// "if x then y else z"

// Church numeral 2
print_term(parse("λf.λx.f (f x)"))
// "(λf. (λx. (f (f x))))"
\```
```

**Step 2: Commit**

```bash
git add docs/api/reference.md
git commit -m "docs(api): create reference.md extracted from README"
```

---

### Task 6: Write slim README.md (~60 lines)

Replace the 529-line README.md with a concise overview that links to detail docs.

**Files:**
- Modify: `README.md`

**Step 1: Overwrite README.md**

```markdown
# Parser Module

Lexer and incremental parser for Lambda Calculus with arithmetic and conditionals.
Produces a lossless CST via `seam` (green-tree infrastructure), a typed AST,
and re-parses incrementally on edits via `ParserDb`.

## Quick Start

\```bash
moon test           # 363 tests
moon check          # lint
moon info && moon fmt  # before commit
moon bench --release   # benchmarks (always --release)
\```

## Documentation

- [docs/README.md](docs/README.md) — full navigation index
- [ROADMAP.md](ROADMAP.md) — architecture, phase status, future work
- [docs/architecture/overview.md](docs/architecture/overview.md) — layer diagram + principles
- [docs/api/reference.md](docs/api/reference.md) — public API reference
- [docs/architecture/language.md](docs/architecture/language.md) — grammar and syntax

## Module Map

| Package | Purpose |
|---------|---------|
| `src/lexer/` | Tokenizer + incremental `TokenBuffer` |
| `src/parser/` | CST parser, CST→AST conversion, lambda `LanguageSpec` |
| `src/seam/` | Language-agnostic CST (`CstNode`, `SyntaxNode`, `EventBuffer`) |
| `src/core/` | `Edit`, `Range`, `ReuseSlot`, `Editable` — shared primitives |
| `src/ast/` | `AstNode`, `Term`, pretty-printer |
| `src/pipeline/` | `ParserDb` — reactive incremental pipeline |
| `src/incremental/` | `IncrementalParser`, damage tracking |
| `src/viz/` | DOT graph renderer (`DotNode` trait) |
| `src/lambda/` | Lambda-specific `LambdaLanguage`, `LambdaParserDb` |

## Benchmarks

\```bash
moon bench --package dowdiness/parser/benchmarks --release
\```

Key benchmarks: `incremental vs full` (start/middle/end), `worst-case full
invalidation`, `best-case cosmetic change`. See [BENCHMARKS.md](BENCHMARKS.md).

## Testing

\```bash
moon test                                      # all 363 tests
moon test --filter '*differential-fast*'       # CI-friendly differential
moon test --filter '*differential-long*'       # nightly fuzz pass
\```
```

**Step 2: Verify line count**

```bash
wc -l /home/antisatori/ghq/github.com/dowdiness/crdt/parser/README.md
```

Expected: < 80 lines

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: slim README.md from 529 to ~60 lines, extract detail to docs/"
```

---

### Task 7: Extract ROADMAP.md phase 0-4 detail to archive

Create `docs/archive/completed-phases/phases-0-4.md` with the extracted detail, then slim ROADMAP.md phases 0-4 to one-paragraph summaries.

**Files:**
- Create: `docs/archive/completed-phases/phases-0-4.md`
- Modify: `ROADMAP.md`

**Step 1: Read ROADMAP.md lines 149–779**

Read the file at offset 149, limit 631 to get the full Phase 0–4 content. This will be the content of `docs/archive/completed-phases/phases-0-4.md`.

**Step 2: Create docs/archive/completed-phases/phases-0-4.md**

Write a new file with header:

```markdown
# Completed Phases 0–4: Implementation Detail

> These are the full implementation notes for Phases 0–4 of the incremental
> parser. All phases are complete. For current architecture status see
> [ROADMAP.md](../../ROADMAP.md).
```

Followed by the full extracted content of ROADMAP.md §Phase 0 through §Phase 4 (all detail preserved, nothing deleted).

**Step 3: Replace ROADMAP.md §Phase 0-4 with brief summaries**

Replace the ~630 lines of Phase 0–4 detail with this compact block:

```markdown
## Phase 0: Architectural Reckoning ✅ COMPLETE (2026-02-01)

Removed all dead cache infrastructure (`TokenCache`, `ParseCache`, `RecoveringParser` — ~581 lines).
Parser now honestly does: damage tracking → whole-tree reuse check → full reparse.
[Full notes →](docs/archive/completed-phases/phases-0-4.md#phase-0)

---

## Phase 1: Incremental Lexer ✅ COMPLETE (2026-02-02)

Splice-based `TokenBuffer` re-lexes only the damaged region (typically ~50 bytes for a 1-char edit
in a 10KB file) and splices the result into the existing token array. Implemented in `src/lexer/token_buffer.mbt`.
[Full notes →](docs/archive/completed-phases/phases-0-4.md#phase-1)

---

## Phase 2: Green Tree (Immutable CST) ✅ COMPLETE (2026-02-19)

`CstNode` (position-independent, content-addressed, structurally shareable) + `SyntaxNode` (ephemeral
positioned facade) + `EventBuffer` (flat event stream → tree) + `seam/` package. Enables
pointer-equality structural sharing: unchanged subtrees are the same object, not copies.
[Full notes →](docs/archive/completed-phases/phases-0-4.md#phase-2)

---

## Phase 3: Integrated Error Recovery ✅ COMPLETE (2026-02-03)

Sync-point recovery (`RightParen`, `Then`, `Else`, `EOF`). Parser produces partial trees with
`ErrorNode`/`ErrorToken` interspersed among valid nodes. Reports up to 50 errors per parse.
Fuzz-tested for termination on any token sequence.
[Full notes →](docs/archive/completed-phases/phases-0-4.md#phase-3)

---

## Phase 4: Checkpoint-Based Subtree Reuse ✅ COMPLETE (2026-02-03)

`ReuseCursor` with 4-condition reuse protocol: kind match + leading token context + trailing
token context + no damage overlap. Trailing context check is essential (a node's parse can
depend on what follows it). O(depth) per lookup via stateful frame stack.
[Full notes →](docs/archive/completed-phases/phases-0-4.md#phase-4)

---
```

**Step 4: Update ROADMAP.md header updated date**

Change `**Updated:** 2026-02-25` to `**Updated:** 2026-02-28`.

**Step 5: Verify ROADMAP.md line count**

```bash
wc -l /home/antisatori/ghq/github.com/dowdiness/crdt/parser/ROADMAP.md
```

Expected: ~450 lines (down from 1,250)

**Step 6: Commit**

```bash
git add ROADMAP.md docs/archive/completed-phases/phases-0-4.md
git commit -m "docs: slim ROADMAP.md phases 0-4 to summaries, extract detail to archive"
```

---

### Task 8: Create docs/architecture/overview.md

Extract the target architecture diagram and principles from ROADMAP.md §Target Architecture (lines 77-147).

**Files:**
- Create: `docs/architecture/overview.md`

**Step 1: Create the file**

```markdown
# Architecture Overview

See also: [pipeline detail](pipeline.md) | [seam model](seam-model.md) | [generic parser](generic-parser.md)

## Layer Diagram

\```
                    +-----------------------+
                    |     Edit Protocol     |
                    |  (apply, get_tree)    |
                    +-----------+-----------+
                                |
                    +-----------v-----------+
                    |   Incremental Engine  |
                    |   - Damage tracking   |
                    |   - Reuse decisions   |
                    |   - Orchestration     |
                    +-----------+-----------+
                                |
              +-----------------+------------------+
              |                                    |
   +----------v----------+            +-----------v-----------+
   |  Incremental Lexer  |            |  Incremental Parser   |
   |  - Token buffer     |            |  - Subtree reuse at   |
   |  - Edit-aware       |            |    grammar boundaries |
   |  - Only re-lex      |            |  - Checkpoint-based   |
   |    damaged region   |            |    validation         |
   +----------+----------+            +-----------+-----------+
              |                                    |
   +----------v----------+            +-----------v-----------+
   |    Token Buffer     |            |   Green Tree (CST)    |
   |  - Contiguous array |            |  - Immutable nodes    |
   |  - Position-tracked |            |  - Structural sharing |
   |  - Cheaply sliceable|            |  - Lossless syntax    |
   +---------------------+            +-----------+-----------+
                                                  |
                                      +-----------v-----------+
                                      |   Red Tree (Facade)   |
                                      |  - Absolute positions |
                                      |  - Parent pointers    |
                                      |  - On-demand          |
                                      +-----------+-----------+
                                                  |
                                      +-----------v-----------+
                                      |   Typed AST (Lazy)    |
                                      |  - Semantic analysis  |
                                      |  - Derived from CST   |
                                      +-----------------------+
\```

## Architectural Principles

1. **No dead infrastructure.** Every component must be read during the parse pipeline.

2. **Immutability enables sharing.** Green tree nodes are immutable — unchanged nodes are the same pointer, not a copy.

3. **Separation of structure and position.** Green nodes store widths (relative). Red nodes compute absolute positions on demand. Structural identity is independent of position.

4. **Incremental lexing is the first real win.** Re-tokenizing only the damaged region gives the parser unchanged tokens for free.

5. **Subtree reuse at grammar boundaries.** At each grammar boundary: does the old subtree's kind match? Are both leading and trailing token contexts unchanged? If so, skip parsing and reuse. Trailing context is essential — a node's parse can depend on what follows it.

6. **Error recovery is part of the parser, not around it.** The parser records errors, synchronizes to known points, and continues.
```

**Step 2: Commit**

```bash
git add docs/architecture/overview.md
git commit -m "docs(architecture): create overview.md with layer diagram and principles"
```

---

### Task 9: Rewrite docs/README.md as navigation index

Replace the current 42-line flat index with a hierarchical navigation document.

**Files:**
- Modify: `docs/README.md`

**Step 1: Write new docs/README.md**

```markdown
# Documentation Index

Navigation map for the incremental parser. Start here, go one level deeper for detail.

## Architecture

Understanding how the layers fit together:

- [overview.md](architecture/overview.md) — layer diagram, architectural principles
- [pipeline.md](architecture/pipeline.md) — parse pipeline step by step
- [language.md](architecture/language.md) — grammar, syntax, Token/Term data types
- [seam-model.md](architecture/seam-model.md) — `CstNode`/`SyntaxNode` two-tree model
- [generic-parser.md](architecture/generic-parser.md) — `LanguageSpec`, `ParserContext` API

## API Reference

- [api/reference.md](api/reference.md) — all public functions, error types, examples
- [api/api-contract.md](api/api-contract.md) — API contract and stability guarantees
- [api/pipeline-api-contract.md](api/pipeline-api-contract.md) — pipeline API contract

## Correctness

- [correctness/CORRECTNESS.md](correctness/CORRECTNESS.md) — correctness goals and verification
- [correctness/STRUCTURAL_VALIDATION.md](correctness/STRUCTURAL_VALIDATION.md) — structural validation details
- [correctness/EDGE_CASE_TESTS.md](correctness/EDGE_CASE_TESTS.md) — edge-case test catalog

## Performance

- [performance/PERFORMANCE_ANALYSIS.md](performance/PERFORMANCE_ANALYSIS.md) — benchmarks and analysis
- [performance/benchmark_history.md](performance/benchmark_history.md) — historical benchmark log

## Architecture Decisions (ADRs)

- [decisions/2026-02-27-remove-tokenStage-memo.md](decisions/2026-02-27-remove-tokenStage-memo.md)
- [decisions/2026-02-28-edit-lengths-not-endpoints.md](decisions/2026-02-28-edit-lengths-not-endpoints.md)

## Active Plans (Future Work)

- [plans/2026-02-25-node-interner-design.md](plans/2026-02-25-node-interner-design.md)
- [plans/2026-02-25-node-interner.md](plans/2026-02-25-node-interner.md)
- [plans/2026-02-25-syntax-node-extend.md](plans/2026-02-25-syntax-node-extend.md)
- [plans/2026-02-25-syntax-node-first-layer-design.md](plans/2026-02-25-syntax-node-first-layer-design.md)

## Archive (Historical / Completed)

- [archive/completed-phases/phases-0-4.md](archive/completed-phases/phases-0-4.md) — Phases 0–4 full implementation notes
- [archive/completed-phases/](archive/completed-phases/) — all completed phase plan files
- [archive/LEZER_IMPLEMENTATION.md](archive/LEZER_IMPLEMENTATION.md) — Lezer study notes
- [archive/LEZER_FRAGMENT_REUSE.md](archive/LEZER_FRAGMENT_REUSE.md) — fragment reuse research
- [archive/green-tree-extraction.md](archive/green-tree-extraction.md)
- [archive/IMPLEMENTATION_SUMMARY.md](archive/IMPLEMENTATION_SUMMARY.md)
- [archive/IMPLEMENTATION_COMPLETE.md](archive/IMPLEMENTATION_COMPLETE.md)
- [archive/COMPLETION_SUMMARY.md](archive/COMPLETION_SUMMARY.md)
- [archive/TODO_ARCHIVE.md](archive/TODO_ARCHIVE.md)
```

**Step 2: Commit**

```bash
git add docs/README.md
git commit -m "docs: rewrite docs/README.md as hierarchical navigation index"
```

---

## Verification

After all tasks:

```bash
# Check no broken relative links in top-level docs
wc -l README.md ROADMAP.md docs/README.md
# Expected: README ~60, ROADMAP ~450, docs/README ~55

# Confirm only active plans remain
ls docs/plans/

# Confirm archive has completed phases
ls docs/archive/completed-phases/

# Tests still pass (no code changed)
moon test
```

Expected `wc -l` output:
```
  ~60 README.md
 ~450 ROADMAP.md
  ~55 docs/README.md
```
