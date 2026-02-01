# Roadmap: Stabilized Incremental Parser

**Created:** 2026-02-01
**Status:** Active
**Goal:** A genuinely incremental, architecturally sound parser for lambda calculus (and beyond) with confidence in every layer.

---

## Honest Assessment of Current State

Before planning forward, we need an unflinching look at where we are. The existing codebase has good bones in some areas but critical gaps in others.

### What Actually Works

1. **Recursive descent parser** (`parser.mbt:72-227`) - Correct, clean, well-tested. Produces `TermNode` with position tracking. This is solid.

2. **Lexer** (`lexer.mbt`) - Correct tokenization with position tracking (`TokenInfo`). Handles Unicode lambda, keywords, multi-digit integers.

3. **Damage tracking** (`damage.mbt`) - Wagner-Graham algorithm correctly identifies damaged ranges after edits. The algorithm is sound.

4. **Position adjustment** (`incremental_parser.mbt:144-186`) - Correctly shifts tree node positions after edits. Handles before/after/overlapping cases.

5. **Data structures** - `TermNode`, `TermKind`, `Edit`, `Range` are well-designed and tested.

6. **Test suite** - 223 tests passing, including property-based tests. Good coverage.

### What Does Not Work (Architectural Dead Weight)

**Critical finding: The caches are never consulted during parsing.**

- `TokenCache` (`token_cache.mbt`) stores tokens and invalidates ranges, but `tokenize()` in `lexer.mbt` never calls `TokenCache::get()`. Every parse does a full re-tokenization regardless.

- `ParseCache` (`parse_cache.mbt`) stores parse results and invalidates ranges, but `parse_tree()` in `parser.mbt` never calls `ParseCache::get()`. Every parse does a full parse regardless.

- The only callers of `cache.get()` are test files and benchmarks - never production code.

**This means the "incremental" parser is actually:**
1. Track damage (works)
2. Invalidate cache entries that nothing reads (no-op)
3. Check whole-tree reuse (rare optimization)
4. Fall through to full reparse (almost always)

The cache invalidation that the documentation claims "provides 70-80% of incremental benefits" provides **zero benefits** because the parser never reads from the caches. The performance numbers in the docs reflect full-reparse speed on small inputs, not incremental gains.

### Error Recovery is a Wrapper, Not an Integration

`parse_with_error_recovery()` (`error_recovery.mbt:35-61`) wraps `parse_tree()` in a try-catch. If parsing fails at any point, the entire input gets a single error node. There is no:
- Synchronization point recovery inside the parser
- Partial tree construction on error
- Multiple error node insertion
- Recovery continuation after errors

The `RecoveringParser` struct exists but is never used for actual parsing. The parser either succeeds completely or fails completely.

### CRDT Integration is Conceptual

`crdt_integration.mbt` provides `ast_to_crdt()` and `crdt_to_source()` conversion functions. This is a mapping layer, not a CRDT integration. There is no:
- Conflict resolution
- Concurrent edit handling
- Operation-based synchronization
- Actual CRDT data structure

### Summary

| Component | Claimed Status | Actual Status |
|-----------|---------------|---------------|
| Recursive descent parser | Production ready | **Correct** - genuinely works |
| Lexer | Production ready | **Correct** - genuinely works |
| Damage tracking | Production ready | **Correct** - genuinely works |
| Position adjustment | Production ready | **Correct** - genuinely works |
| Token cache | Provides 70-80% benefit | **Dead code** - never read during parsing |
| Parse cache | Preserves subtrees | **Dead code** - never read during parsing |
| Incremental reparse | Cache-based optimization | **Full reparse** every time (except whole-tree reuse) |
| Error recovery | Panic mode with sync points | **Try-catch wrapper** - all-or-nothing |
| CRDT integration | Bridge to collaborative editing | **Conversion functions** - no CRDT logic |

---

## Target Architecture

The end state is a parser where every layer earns its existence. No dead infrastructure. Every component is connected and contributes measurable value.

```
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
                                          +-----------+-----------+
                                                      |
                                          +-----------v-----------+
                                          |   Error Recovery      |
                                          |  - Integrated in      |
                                          |    parser loop        |
                                          |  - Sync point based   |
                                          |  - Multiple errors    |
                                          +-----------------------+
```

### Architectural Principles

1. **No dead infrastructure.** Every cache, buffer, and data structure must be read by something during the parse pipeline. If it's not read, it doesn't exist.

2. **Immutability enables sharing.** Green tree nodes are immutable. When nothing changed, the old node IS the new node - not a copy, the same pointer. This is the foundation of incremental reuse.

3. **Separation of structure and position.** Green tree nodes store widths (relative sizes). Red tree nodes compute absolute positions on demand. This means structural identity is independent of position - moving a subtree doesn't invalidate it.

4. **Incremental lexing is the first real win.** Re-tokenizing only the damaged region, then splicing into the existing token buffer, gives the parser unchanged tokens for free.

5. **Subtree reuse at grammar boundaries.** Recursive descent can't validate arbitrary nodes like LR parsers, but it CAN check: "at this grammar boundary, do the leading tokens match what produced this old subtree?" If yes, skip parsing and reuse.

6. **Error recovery is part of the parser, not around it.** The parser must be able to record an error, synchronize to a known point, and continue parsing the rest of the input.

---

## Phase 0: Architectural Reckoning

**Goal:** Remove all dead infrastructure. Make the codebase honest about what it does. Establish baseline benchmarks that measure real behavior.

### 0.1 Remove Dead Caches

The `TokenCache` and `ParseCache` are never read during parsing. They add ~400 lines of code, complexity to `IncrementalParser`, and false claims in documentation.

**Action:**
- Remove `TokenCache` and `ParseCache` structs and all associated code
- Remove cache fields from `IncrementalParser`
- Remove cache invalidation steps from `IncrementalParser::edit()`
- Update `IncrementalParser::stats()` to reflect actual state
- Update all documentation that references cache benefits

**What survives:** Damage tracking, position adjustment, whole-tree reuse. These actually work.

**Risk:** Tests that directly test cache behavior will be removed. Tests that test parser correctness (the important ones) will be unaffected.

### 0.2 Honest Benchmarks

Create benchmarks that measure what actually happens:

```
Benchmark: "full reparse on edit" (current behavior)
Benchmark: "full reparse on unchanged input" (should be instant with whole-tree reuse)
Benchmark: "position adjustment cost"
Benchmark: "damage tracking cost"
Benchmark: "tokenization cost by input size"
Benchmark: "parsing cost by input size"
```

These baselines will let us measure real improvements in later phases.

### 0.3 Simplify Error Recovery

Remove `RecoveringParser` struct (unused for actual parsing). Keep `parse_with_error_recovery()` but document it honestly as a try-catch wrapper. The real error recovery comes in Phase 4.

### 0.4 Clean Documentation

Update all documentation to reflect the actual state after cleanup. Remove claims about cache benefits, Lezer-style optimization, etc.

**Exit criteria:**
- Zero dead code
- All benchmarks running and baselined
- Documentation matches reality
- All existing correctness tests still pass

---

## Phase 1: Incremental Lexer

**Goal:** Only re-tokenize the damaged region of the source. This is the first optimization that provides real, measurable incremental benefit.

### Why This Comes First

Tokenization is O(n) on source length. For a 10KB file with a 1-character edit, we currently re-tokenize all 10KB. An incremental lexer re-tokenizes perhaps 50 bytes around the edit point and splices the result into the existing token buffer. This is the single largest practical win available.

### 1.1 Token Buffer

Replace the current "tokenize from scratch every time" approach with a persistent token buffer.

```
pub struct TokenBuffer {
  tokens : Array[TokenInfo]       // All tokens, contiguous
  source : String                 // Current source text
  mut version : Int               // Edit counter
}
```

The token buffer is the single source of truth for tokens. It is modified in-place by the incremental lexer.

### 1.2 Incremental Tokenization

When an edit arrives:

1. **Map edit to token range:** Find the first token whose range overlaps or follows `edit.start`, and the last token whose range overlaps or precedes `edit.old_end`. These define the "dirty" token span.

2. **Re-lex the dirty region:** Extract the substring of the new source that covers the dirty region (with some context margin for multi-character tokens). Tokenize just that substring.

3. **Splice:** Replace the dirty token span with the newly lexed tokens. Adjust positions of all tokens after the splice point by the edit delta.

```
Before edit:  [T0][T1][T2][T3][T4][T5][T6]
Edit affects: ............[T2][T3]..........
Re-lex:       ............[T2'][T3'][TX].....
After splice: [T0][T1][T2'][T3'][TX][T4'][T5'][T6']
                                      ^ positions shifted
```

**Key detail:** The re-lex region must extend slightly beyond the edit to handle cases where the edit changes token boundaries (e.g., inserting `f` into `i` to make `if`, changing an identifier into a keyword).

### 1.3 Token Boundary Context

The margin for re-lexing needs to be conservative:
- Extend left to the start of the token containing `edit.start`
- Extend right to the end of the token containing `edit.old_end`, plus one more token (for lookahead effects like keyword boundaries)
- If the edit is at a whitespace/token boundary, extend to include the adjacent tokens

For lambda calculus with single-character operators and short keywords (`if`, `then`, `else`), a context of 6 characters on each side is sufficient.

### 1.4 Integration

Modify `IncrementalParser` to:
1. Maintain a `TokenBuffer` instead of calling `tokenize()` fresh
2. On edit: update token buffer incrementally, then parse
3. On initial parse: fill token buffer from full tokenization

**Exit criteria:**
- Incremental lexer correctly handles all edit types (insert, delete, replace)
- Token buffer matches full re-tokenization for every test case
- Benchmark shows measurable speedup for edits on larger inputs (100+ tokens)
- Property test: for any edit, incremental lex result == full lex result

---

## Phase 2: Green Tree (Immutable CST)

**Goal:** Replace the current mutable `TermNode` with an immutable green tree architecture that enables structural sharing and subtree reuse.

### Why This Architecture

The current `TermNode` stores absolute byte positions (`start`, `end`). When text is inserted before a node, its positions must be updated even though the node's structure hasn't changed. This forces copying the entire tree on every edit.

A green tree stores **widths** (relative sizes) instead of absolute positions. A node that spans 5 bytes has `text_len: 5` regardless of where it appears in the document. This means structurally identical subtrees are literally the same object in memory - no copying needed.

This is the architecture used by:
- Roslyn (C# compiler) - invented the red-green tree
- rust-analyzer - adapted it for Rust
- swift-syntax - adapted it for Swift

It is proven at scale and well-understood.

### 2.1 Green Node Design

```
pub enum GreenElement {
  Token(GreenToken)
  Node(GreenNode)
}

pub struct GreenToken {
  kind : SyntaxKind         // Token type
  text : String             // Actual text (e.g., "lambda", "42", "+")
}

pub struct GreenNode {
  kind : SyntaxKind         // Node type (Expression, Lambda, App, etc.)
  children : Array[GreenElement]
  text_len : Int            // Total width = sum of children widths (cached)
}
```

**Key property:** `GreenNode` has no positions. Two `GreenNode`s with the same kind and children are structurally identical regardless of where they appear in the source.

### 2.2 Syntax Kind Enum

Unify tokens and node types into a single enum:

```
pub enum SyntaxKind {
  // Tokens
  LambdaToken
  DotToken
  LeftParenToken
  RightParenToken
  PlusToken
  MinusToken
  IfKeyword
  ThenKeyword
  ElseKeyword
  IdentToken
  IntToken
  WhitespaceToken      // NEW: preserve whitespace
  ErrorToken           // NEW: for error recovery
  EofToken

  // Composite nodes
  LambdaExpr           // λx.body
  AppExpr              // f x
  BinaryExpr           // a + b
  IfExpr               // if c then t else e
  ParenExpr            // (expr)
  IntLiteral
  VarRef
  ErrorNode            // Error recovery container

  // Root
  SourceFile
}
```

### 2.3 Red Node (Position Facade)

Red nodes wrap green nodes and compute absolute positions on demand:

```
pub struct RedNode {
  green : GreenNode         // The underlying immutable node
  parent : RedNode?         // Parent (for traversal)
  offset : Int              // Absolute byte offset in source
}
```

Red nodes are created lazily when you need to answer "what is the absolute position of this node?" They are ephemeral - not stored persistently.

### 2.4 Builder Pattern

The parser constructs green trees using a builder that manages the stack:

```
pub struct TreeBuilder {
  stack : Array[Array[GreenElement]]  // Stack of in-progress children lists
}

fn TreeBuilder::start_node(self, kind : SyntaxKind)
fn TreeBuilder::finish_node(self) -> GreenNode
fn TreeBuilder::token(self, kind : SyntaxKind, text : String)
```

### 2.5 Structural Sharing

When the incremental parser determines a subtree is unchanged (Phase 4), it reuses the old `GreenNode` directly:

```
// Old tree: Lambda("x", App(Var("x"), Int(1)))
// Edit: change "1" to "2"
// New tree: Lambda("x", App(Var("x"), Int(2)))
//
// The Lambda node is new (different child)
// The App node is new (different child)
// BUT Var("x") is the SAME GreenNode object - not a copy
```

This is O(depth) allocation for a leaf change, not O(tree_size).

### 2.6 Migration Path

1. Implement `GreenNode`, `GreenToken`, `GreenElement`, `SyntaxKind`
2. Implement `TreeBuilder`
3. Modify parser to use `TreeBuilder` instead of direct `TermNode` construction
4. Implement `RedNode` for position queries
5. Provide `green_to_term()` conversion to maintain backward compatibility
6. Migrate tests incrementally

**Exit criteria:**
- Green tree correctly represents all parsed programs
- Red node positions match current `TermNode` positions for all test cases
- Structural sharing verified: unchanged subtrees are pointer-equal
- No performance regression on current benchmarks
- All existing semantic tests pass through compatibility layer

---

## Phase 3: Integrated Error Recovery

**Goal:** The parser continues past errors, producing a tree with error nodes interspersed among correctly parsed nodes. Multiple errors in a single parse.

### Why Before Subtree Reuse

Subtree reuse (Phase 4) depends on knowing where grammar boundaries are. Error recovery defines those boundaries. If the parser can't recover from errors, it can't establish the stable points needed for reuse decisions.

### 3.1 Synchronization Points

Define synchronization tokens for lambda calculus:

```
fn is_sync_point(kind : SyntaxKind) -> Bool {
  match kind {
    RightParenToken => true    // End of parenthesized expression
    EofToken => true           // End of input
    LambdaToken => true        // Start of new lambda
    IfKeyword => true          // Start of new if-expression
    _ => false
  }
}
```

When the parser encounters an unexpected token:
1. Record the error with position information
2. Wrap consumed tokens in an `ErrorNode`
3. Skip tokens until a synchronization point
4. Resume parsing from the synchronization point

### 3.2 Error Productions

Add explicit error handling in the parser at key points:

```
// In parse_atom:
fn parse_atom(p : Parser) -> GreenNode {
  match p.current() {
    IntToken => ...
    IdentToken => ...
    LambdaToken => ...
    IfKeyword => ...
    LeftParenToken => ...
    _ => {
      // Error: unexpected token
      p.error("expected expression")
      p.bump_as(ErrorToken)  // Consume the bad token as an error
      // Parser continues - caller handles what comes next
    }
  }
}
```

### 3.3 Missing Token Insertion

For expected tokens that are missing:

```
fn expect(p : Parser, expected : SyntaxKind) {
  if p.current() == expected {
    p.bump()
  } else {
    p.error("expected " + expected.to_string())
    // Don't consume - the token might be valid for the parent rule
    // Insert a zero-width error marker
    p.insert_missing(expected)
  }
}
```

### 3.4 Error Budget

Prevent infinite loops from cascading errors:

```
const MAX_ERRORS : Int = 50

fn Parser::error(self, message : String) {
  if self.error_count < MAX_ERRORS {
    self.errors.push(ParseError::new(message, self.position()))
    self.error_count += 1
  }
}
```

### 3.5 Outcome

After this phase, given input like `λx. + y`, the parser produces:

```
SourceFile
  LambdaExpr
    LambdaToken "λ"
    IdentToken "x"
    DotToken "."
    ErrorNode
      ErrorToken "+"         // unexpected "+" recorded as error
    VarRef
      IdentToken "y"         // parsing continued and found "y"
```

Instead of the current behavior: single error node for entire input.

**Exit criteria:**
- Parser produces partial trees for all current error test cases
- Multiple errors reported for inputs with multiple problems
- Parser never panics or enters infinite loop on any input
- All valid inputs still parse identically to current behavior
- Fuzzing with random inputs: parser always terminates, always produces a tree

---

## Phase 4: Checkpoint-Based Subtree Reuse

**Goal:** When re-parsing after an edit, reuse unchanged subtrees from the previous parse. This is the core incremental parsing capability.

### The Key Insight for Recursive Descent

LR parsers can validate subtree reuse using goto tables. We don't have goto tables. But we have something LR parsers don't: **we know exactly which grammar rule we're in.**

At the top of `parse_atom()`, we know we're parsing an atom. If we have an old `GreenNode` of kind `IntLiteral` at the current position, and the leading token is `IntToken` with the same text, we know the old subtree is valid. We don't need a goto table - the call stack IS our parser state.

### 4.1 Reuse Cursor

A cursor that walks the old tree in parallel with parsing:

```
pub struct ReuseCursor {
  old_tree : GreenNode          // Previous parse tree
  stack : Array[CursorFrame]    // Position within old tree
  offset : Int                  // Current byte offset in old source
}

struct CursorFrame {
  node : GreenNode
  child_index : Int
}
```

The cursor advances through the old tree's children as the parser advances through tokens. When the parser enters a grammar rule, it asks the cursor: "do you have a node of this kind at this position?"

### 4.2 Reuse Protocol

At each grammar boundary (start of `parse_expression`, `parse_atom`, etc.):

```
fn try_reuse(p : Parser, cursor : ReuseCursor, expected_kind : SyntaxKind) -> GreenNode? {
  let candidate = cursor.current_node()

  // Check 1: Is there an old node here?
  guard candidate != None

  // Check 2: Is it the right kind?
  guard candidate.kind == expected_kind

  // Check 3: Is it outside the damaged range?
  let node_end = cursor.offset + candidate.text_len
  guard !damaged_range.overlaps(Range::new(cursor.offset, node_end))

  // Check 4: Do the leading tokens match?
  // (Catches cases where context change makes old parse invalid)
  guard p.current_token_text() == first_token_text(candidate)

  // Reuse! Skip the parser ahead by this node's width
  p.advance_by(candidate.text_len)
  cursor.advance_past(candidate)
  Some(candidate)
}
```

### 4.3 Integration Points

Add reuse checks at the top of each parse function:

```
fn parse_atom(p : Parser) -> GreenNode {
  // Try to reuse old subtree
  if let Some(reused) = try_reuse(p, cursor, IntLiteral) { return reused }
  if let Some(reused) = try_reuse(p, cursor, VarRef) { return reused }
  if let Some(reused) = try_reuse(p, cursor, LambdaExpr) { return reused }
  if let Some(reused) = try_reuse(p, cursor, IfExpr) { return reused }
  if let Some(reused) = try_reuse(p, cursor, ParenExpr) { return reused }

  // No reuse possible, parse fresh
  match p.current() {
    IntToken => ...
    ...
  }
}
```

### 4.4 Damaged Range Awareness

The reuse cursor tracks which parts of the old tree overlap the damaged range:

- Nodes completely before the damage: reusable (position already adjusted)
- Nodes overlapping the damage: must re-parse
- Nodes completely after the damage: reusable (positions shifted by delta)

The damage tracking from the current implementation (`damage.mbt`) feeds directly into this decision.

### 4.5 Correctness Invariant

**The fundamental correctness property:** For any edit, the incremental parse produces a tree that is structurally identical to a full re-parse of the new source.

This is tested by:
```
test "incremental matches full reparse" {
  // For every test input and every possible edit:
  let full = parse(new_source)
  let incremental = parser.edit(edit, new_source)
  assert_structurally_equal(full, incremental)
}
```

### 4.6 Performance Target

For a localized edit (changing a single token) in a file with N tokens:
- **Current:** O(N) tokenization + O(N) parsing = O(N) total
- **After Phase 1:** O(1) tokenization + O(N) parsing = O(N) total
- **After Phase 4:** O(1) tokenization + O(depth) tree construction = O(log N) typical

The improvement comes from reusing O(N - depth) subtrees and only constructing O(depth) new nodes along the path from root to the edited leaf.

**Exit criteria:**
- Incremental parse matches full reparse for all test inputs and edits
- Measurable reduction in parse time for localized edits on larger inputs
- Reuse rate > 80% for single-token edits on files with 100+ tokens
- Property test: for random edits, incremental == full reparse
- No correctness regressions

---

## Phase 5: Grammar Expansion and CST Maturity

**Goal:** Expand the language beyond bare lambda calculus. Each new construct creates more natural boundaries for incremental reuse.

### 5.1 Let Bindings

```
let x = expr in body
```

Let bindings are the most important expansion because they create **top-level boundaries**. A file with multiple let bindings:

```
let id = λx.x
let two = λf.λx.f (f x)
let result = id two
```

Each let binding is an independent subtree. Editing `id` doesn't require re-parsing `two` or `result`. This is where incremental parsing has massive impact.

Grammar addition:
```
Expression ::= 'let' Identifier '=' Expression 'in' Expression
             | BinaryOp
```

### 5.2 Type Annotations

```
let id : (a -> a) = λx.x
```

Type annotations add structure that helps both error recovery (more synchronization points) and incremental reuse (type signatures are often unchanged).

### 5.3 Comments

```
-- This is a comment
let id = λx.x  -- inline comment
```

Comments are preserved in the CST as `CommentToken` green nodes. They participate in whitespace trivia but don't affect the semantic tree.

### 5.4 Multi-Expression Files

Support files with multiple top-level definitions separated by newlines or semicolons:

```
SourceFile
  LetDecl
    ...
  LetDecl
    ...
  Expression
    ...
```

This is the structure that makes incremental parsing most valuable - editing one declaration doesn't touch others.

### 5.5 Whitespace Trivia

In the CST, whitespace and comments attach to tokens as leading/trailing trivia:

```
GreenToken {
  kind: IdentToken,
  leading_trivia: [WhitespaceToken("  ")],
  text: "x",
  trailing_trivia: [WhitespaceToken(" "), CommentToken("-- variable")]
}
```

This makes the CST fully lossless - you can reconstruct the original source exactly from the CST, including all whitespace and comments.

**Exit criteria:**
- Let bindings, type annotations, and comments fully supported
- Multi-expression files parse correctly
- CST round-trips to identical source text
- Incremental reuse works across let-binding boundaries
- All new constructs have comprehensive tests

---

## Phase 6: CRDT Integration (Genuine)

**Goal:** Connect the incremental parser to actual CRDT operations for collaborative editing.

### 6.1 Operation-Based Updates

Instead of the current "convert entire AST to CRDT node" approach, generate minimal CRDT operations from tree diffs:

```
fn diff_trees(old : GreenNode, new : GreenNode) -> Array[CRDTOp] {
  if old == new { return [] }  // Pointer equality! (green tree sharing)

  // Only generate operations for structurally different subtrees
  ...
}
```

The green tree architecture makes this efficient: pointer-equal subtrees are identical, so diff can skip them in O(1).

### 6.2 Edit Reconciliation

When a remote CRDT operation arrives:
1. Apply the operation to the source text
2. Construct an `Edit` from the text change
3. Feed through the incremental parser
4. Diff the new tree against the old to confirm convergence

### 6.3 Conflict Resolution

For concurrent edits that affect the same syntactic region:
- Text-level: CRDT handles character ordering
- Parse-level: re-parse the affected region after CRDT merge
- Tree-level: the incremental parser naturally produces the correct tree for the merged text

**Exit criteria:**
- Concurrent edits produce converging parse trees
- Operation generation is proportional to edit size, not file size
- Integration tests with simulated concurrent editing scenarios

---

## Phase Summary and Dependencies

```
Phase 0: Reckoning          (no dependencies - cleanup)
    |
Phase 1: Incremental Lexer  (depends on Phase 0)
    |
Phase 2: Green Tree         (depends on Phase 0, parallel with Phase 1)
    |
Phase 3: Error Recovery     (depends on Phase 2)
    |
Phase 4: Subtree Reuse      (depends on Phase 1, 2, 3)
    |
Phase 5: Grammar Expansion  (depends on Phase 2, 3)
    |
Phase 6: CRDT Integration   (depends on Phase 2, 4)
```

Phases 1 and 2 can proceed in parallel after Phase 0.
Phases 5 and 6 can proceed in parallel after their dependencies.

---

## Milestones and Confidence Levels

### Milestone 1: Honest Foundation (Phase 0)
**Confidence: Certain**

Removing dead code and establishing honest benchmarks requires no architectural risk. This is purely cleanup work.

### Milestone 2: Incremental Lexer (Phase 1)
**Confidence: High**

Incremental lexing is well-understood. The lambda calculus lexer is simple (no multi-line tokens, no context-dependent lexing, no string interpolation). The main work is splicing logic and boundary handling.

Known risk: Token boundary detection when edits create or destroy multi-character tokens (e.g., `if` keyword). Mitigated by conservative context margins.

### Milestone 3: Green Tree (Phase 2)
**Confidence: High**

The red-green tree architecture is proven in production compilers (Roslyn, rust-analyzer, swift-syntax). The design is well-documented. The main work is migrating the parser to use a tree builder.

Known risk: Performance characteristics in MoonBit may differ from Rust/C#. Mitigated by benchmarking early and adjusting allocation strategies.

### Milestone 4: Error Recovery (Phase 3)
**Confidence: Medium-High**

Synchronization-point error recovery in recursive descent is well-established. The challenge is choosing good synchronization points for lambda calculus (which has few keywords) and avoiding cascading errors.

Known risk: Lambda calculus has less syntactic structure than typical programming languages, making recovery points scarcer. Mitigated by parentheses and keywords (`if`/`then`/`else`) as anchors.

### Milestone 5: Subtree Reuse (Phase 4)
**Confidence: Medium**

This is the most novel part. Checkpoint-based reuse in hand-written recursive descent is less established than LR-based reuse. The approach is sound in principle (the call stack provides parser state), but the implementation details matter.

Known risks:
- Context sensitivity: An expression that parses as application in one context might parse as something else in another. The leading-token check mitigates this but may need refinement.
- Reuse cursor synchronization: Keeping the cursor aligned with the parser requires careful bookkeeping.
- Edge cases at edit boundaries.

Mitigated by: The correctness invariant (incremental == full reparse) catches all bugs. Extensive property-based testing.

### Milestone 6: Grammar Expansion (Phase 5)
**Confidence: High**

Adding let bindings and type annotations to a recursive descent parser is straightforward. The green tree architecture supports new node kinds naturally.

### Milestone 7: CRDT Integration (Phase 6)
**Confidence: Medium**

The CRDT integration depends on having a solid diff algorithm for green trees and a well-defined operation model. The theoretical foundation is sound but the implementation complexity is significant.

---

## What This Roadmap Does NOT Include

1. **Parser generation.** We are staying with hand-written recursive descent. This means we accept that we cannot match Lezer/tree-sitter's reuse granularity. We compensate with the green tree architecture and checkpoint-based reuse, which provide sufficient incrementality for our use case.

2. **GLR or Earley parsing.** The grammar is unambiguous. We don't need generalized parsing.

3. **Language server protocol.** This roadmap covers the parser, not IDE integration. An LSP layer would sit on top of Phase 5's CST.

4. **Evaluation / type checking.** This is a parser roadmap, not a language implementation roadmap.

---

## Success Criteria for "Stabilized"

The parser is stabilized when:

1. **Correctness:** Incremental parse produces identical trees to full reparse for any edit, verified by property-based testing over millions of random edits.

2. **Performance:** Single-character edits in a 1000-token file complete in under 100 microseconds (not counting initial parse).

3. **Error resilience:** Any input (including random bytes) produces a tree without panicking. Valid portions of malformed input are correctly parsed.

4. **Architecture:** Every component is connected and contributes to the pipeline. No dead infrastructure. New grammar rules can be added by modifying only the parser and syntax kind enum.

5. **Test coverage:** >95% line coverage on parser, lexer, tree builder, and incremental engine. Property-based tests for all invariants.

6. **Documentation:** Every public API has doc comments. Architecture decisions are documented with rationale. No misleading claims about capabilities.

---

## References

### Architecture Inspiration
- [Roslyn's Red-Green Trees](https://ericlippert.com/2012/06/08/red-green-trees/) - Original red-green tree design
- [rust-analyzer Architecture](https://github.com/rust-lang/rust-analyzer/blob/master/docs/dev/syntax.md) - Practical adaptation for Rust
- [swift-syntax](https://github.com/apple/swift-syntax) - Swift's green tree implementation

### Incremental Parsing
- Wagner & Graham (1998) - [Efficient and Flexible Incremental Parsing](https://harmonia.cs.berkeley.edu/papers/twagner-parsing.pdf)
- [Lezer](https://lezer.codemirror.net/) - LR-based incremental parsing (inspiration, not template)
- [Tree-sitter](https://tree-sitter.github.io/) - Generated recursive descent with incrementality

### Error Recovery
- [Error Recovery in Recursive Descent Parsers](https://www.cs.tufts.edu/~nr/cs257/archive/donn-seeley/repair.pdf)
- [Panic Mode Recovery](https://en.wikipedia.org/wiki/Panic_mode) - Classical approach we adapt

### MoonBit
- [MoonBit Language Reference](https://www.moonbitlang.com/docs/syntax)
- [MoonBit Core Libraries](https://mooncakes.io/docs/#/moonbitlang/core/)
