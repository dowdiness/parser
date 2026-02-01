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

4. **Position adjustment** (`incremental_parser.mbt:144-186`) - Shifts tree node positions after edits. Handles before/after/overlapping cases. **Caveat:** When a node overlaps the edit, the code adjusts children recursively but does NOT adjust the overlapping node's own `end` by the edit delta (lines 172-184). This is harmless today because overlapping nodes are always fully reparsed, but it would be a bug if Phase 4's subtree reuse tried to use the adjusted tree for granular decisions. The green tree architecture (Phase 2) makes this moot by using widths instead of absolute positions.

5. **Data structures** - `TermNode`, `TermKind`, `Edit`, `Range` are well-designed and tested.

6. **Test suite** - 223 tests passing, including property-based tests. Good coverage.

### What Does Not Work (Architectural Gaps)

**Phase 0 (completed 2026-02-01) removed the dead cache infrastructure.** `TokenCache`, `ParseCache`, and `RecoveringParser` have been deleted. The incremental parser now honestly does:
1. Track damage (works)
2. Check whole-tree reuse (works when damage is outside tree bounds)
3. Full reparse (fallback for all other cases)

### Error Recovery is a Wrapper, Not an Integration

`parse_with_error_recovery()` wraps `parse_tree()` in a try-catch. If parsing fails at any point, the entire input gets a single error node. There is no:
- Synchronization point recovery inside the parser
- Partial tree construction on error
- Multiple error node insertion
- Recovery continuation after errors

### CRDT Integration is Conceptual

`crdt_integration.mbt` provides `ast_to_crdt()` and `crdt_to_source()` conversion functions. This is a mapping layer, not a CRDT integration. There is no:
- Conflict resolution
- Concurrent edit handling
- Operation-based synchronization
- Actual CRDT data structure

### Summary

| Component | Status |
|-----------|--------|
| Recursive descent parser | **Correct** - genuinely works |
| Lexer | **Correct** - genuinely works |
| Damage tracking | **Correct** - genuinely works |
| Position adjustment | **Correct** - genuinely works |
| ~~Token cache~~ | **Deleted** (Phase 0) - was never read during parsing |
| ~~Parse cache~~ | **Deleted** (Phase 0) - was never read during parsing |
| Incremental reparse | **Full reparse** fallback (whole-tree reuse when applicable) |
| Error recovery | **Try-catch wrapper** - all-or-nothing |
| CRDT integration | **Conversion functions** - no CRDT logic |

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

5. **Subtree reuse at grammar boundaries.** Recursive descent can't validate arbitrary nodes like LR parsers, but it CAN check: "at this grammar boundary, does the old subtree's kind match, and are both the leading and trailing token contexts unchanged?" If all checks pass, skip parsing and reuse. The trailing context check is essential because a node's parse can depend on what follows it (see Phase 4, section 4.2.1).

6. **Error recovery is part of the parser, not around it.** The parser must be able to record an error, synchronize to a known point, and continue parsing the rest of the input.

---

## Phase 0: Architectural Reckoning ✅ COMPLETE (2026-02-01)

**Goal:** Remove all dead infrastructure. Make the codebase honest about what it does.

### What was done:

- **Deleted** `token_cache.mbt`, `token_cache_test.mbt`, `parse_cache.mbt`, `parse_cache_test.mbt` (~581 lines)
- **Deleted** `RecoveringParser` struct from `error_recovery.mbt`; replaced with plain `Array[String]`
- **Removed** `token_cache` and `parse_cache` fields from `IncrementalParser`
- **Removed** cache invalidation from `IncrementalParser::edit()`
- **Removed** duplicate tokenization from `parse_with_error_recovery()`
- **Simplified** `IncrementalParser::stats()` to report only source length
- **Removed** cache-specific tests and benchmarks
- **Updated** documentation to remove cache claims
- **Renamed** "Lezer-style:" test prefixes to honest names

**What survives:** Recursive descent parser, lexer, damage tracking, position adjustment, whole-tree reuse, error recovery wrapper (try-catch), CRDT integration, all correctness tests.

**Exit criteria met:**
- Zero dead code in parsing path
- 149 tests passing
- `moon check` clean
- `.mbti` regenerated

---

## Phase 1: Incremental Lexer

**Goal:** Only re-tokenize the damaged region of the source. This is the first optimization that provides real, measurable incremental benefit.

**Status (2026-02-01): Implemented; benchmarks pending.**

**What’s done:**
- TokenBuffer implemented with splice-based incremental updates (`token_buffer.mbt`)
- Incremental re-lex integration in `IncrementalParser` (uses token buffer, token-based parse)
- Token-range re-lex with conservative boundary expansion (left/right context)
- Property tests: incremental lex == full lex (QuickCheck + deterministic generators)

### Why This Comes First

Tokenization is O(n) on source length. For a 10KB file with a 1-character edit, we currently re-tokenize all 10KB. An incremental lexer re-tokenizes perhaps 50 bytes around the edit point and splices the result into the existing token buffer. This is the single largest practical win available.

### 1.1 Token Buffer

Replace the current "tokenize from scratch every time" approach with a persistent token buffer.

```
pub struct TokenBuffer {
  tokens : Array[TokenInfo]       // All tokens
  source : String                 // Current source text
  mut version : Int               // Edit counter
}
```

The token buffer is the single source of truth for tokens. It is updated incrementally by re-lexing the damaged region and splicing new tokens in.

**Data structure consideration:** Splicing into the middle of a contiguous `Array` is O(N) because all subsequent elements must be shifted. For a file with 10,000 tokens, an edit near the beginning shifts ~10,000 entries. This is still cheaper than full re-tokenization (which scans every character), because an array splice is a `memcpy` while re-tokenization involves character classification, keyword lookup, and `TokenInfo` construction per token. But for very large files, the splice cost may dominate.

**Options if splice becomes a bottleneck** (measure first):
- **Gap buffer:** Maintain a gap at the last edit point. Splices near the gap are O(splice_size). Moving the gap is O(distance).
- **Chunked array:** Store tokens in fixed-size chunks (e.g., 256 tokens). Splice only affects one chunk.
- **Accept O(N) splice:** For lambda calculus files under 1000 tokens, O(N) splice is sub-microsecond. This is the pragmatic starting point.

**Recommendation:** Start with a plain `Array` and add benchmarks. Only switch to gap buffer or chunks if profiling shows splice cost exceeds re-lex cost on realistic inputs.

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

The token-boundary rules above (extend to enclosing token starts/ends) are the correct approach. Do not use a fixed character margin — an identifier can be arbitrarily long, and a fixed margin could split it.

### 1.4 Integration

Modify `IncrementalParser` to:
1. Maintain a `TokenBuffer` instead of calling `tokenize()` fresh
2. On edit: update token buffer incrementally, then parse
3. On initial parse: fill token buffer from full tokenization

**Note (2026-02-01):** Green tree conversion fixes landed for
trailing whitespace coverage and mixed binary operators. See TODO archive.

**Exit criteria:**
- ✅ Incremental lexer correctly handles all edit types (insert, delete, replace)
- ✅ Token buffer matches full re-tokenization for every test case
- ⏳ Benchmark shows measurable speedup for edits on larger inputs (100+ tokens)
- ✅ Property test: for any edit, incremental lex result == full lex result

---

## Phase 2: Green Tree (Immutable CST)

**Goal:** Replace the current mutable `TermNode` with an immutable green tree architecture that enables structural sharing and subtree reuse.

**Status (2026-02-01): Scaffolding complete (types, parser, red nodes, conversion, tests). Integration pending.**

**What's done:**
- `SyntaxKind` enum unifying tokens and node types (`green_tree.mbt`)
- `GreenToken`, `GreenNode`, `GreenElement` core types (`green_tree.mbt`)
- `TreeBuilder` with stack-based construction (`tree_builder.mbt`)
- `GreenParser` / `parse_green()` with whitespace token emission (`green_parser.mbt`)
- `RedNode` wrapper with offset-based position computation (`red_tree.mbt`)
- Green → Term conversion with mixed-operator handling (`green_convert.mbt`)
- `ParenExpr` node kind distinguishes `x` / `(x)` / `((x))` (section 2.6 satisfied)
- 30+ tests: structure, positions, backward compatibility with `parse_tree` (`green_tree_test.mbt`)
- 195 total tests passing

**Remaining before Phase 2 exit:**
- Integrate `parse_green` into primary `parse()` / `parse_tree()` path (replace direct `TermNode` construction)
- Wire `RedNode` for position queries in production code (not just tests)
- Ensure public API compatibility and update docs
- Verify no performance regression on existing benchmarks

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

**Note on `text: String` in `GreenToken`:** Green tokens store the text directly rather than referencing into the source. This is fundamental to the architecture — if tokens stored `(source_offset, length)`, they would be tied to a specific source string, defeating structural sharing. Two identical tokens at different positions would not be equal.

For the current lambda calculus grammar, all tokens are short (max 4 characters for `then`/`else`), so copying text is cheap. However, when Phase 5 adds comments and string literals, long text could be expensive to duplicate. Production systems address this with:
- **Roslyn:** String interning so identical tokens share the same String object
- **rust-analyzer:** `SmolStr` (inline for ≤22 bytes, reference-counted for longer)

MoonBit's string interning behavior should be investigated before Phase 5. If identical string literals are already interned by the runtime, duplicate tokens like `x` appearing 100 times would share backing memory automatically. If not, an explicit interning table or small-string type will be needed.

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

### 2.6 Parser Change: `ParenExpr` Node Kind

The current parser absorbs parentheses — `(42)` produces a node of kind `Int(42)` with the outer positions, losing the structural information that parentheses were present (`parser.mbt:201-217`). This must change for three reasons:

1. **Lossless CST:** Without `ParenExpr`, `x` and `(x)` and `((x))` are indistinguishable in the tree. Source round-tripping is impossible.

2. **Correct structural identity:** In the green tree, structural identity is based on kind + children. If `(x + y)` is stored as `BinaryExpr` (parens absorbed), removing the parentheses wouldn't change the node kind, causing the reuse cursor to incorrectly treat them as the same structure.

3. **Error recovery:** A missing `)` can only be reported if the parser knows it's inside a `ParenExpr`. Without a distinct node kind, there's no partially-parsed state to represent.

**Action:** Modify `parse_atom` to emit `ParenExpr` wrapping the inner expression instead of copying the inner expression's kind. The `ParenExpr` node contains `LeftParenToken`, the inner expression, and `RightParenToken` as children.

### 2.7 Migration Path

1. ✅ Implement `GreenNode`, `GreenToken`, `GreenElement`, `SyntaxKind`
2. ✅ Implement `TreeBuilder`
3. ✅ Implement `GreenParser` using `TreeBuilder` (standalone `parse_green`, not yet replacing `TermNode` path)
4. ✅ **Change parenthesis handling to emit `ParenExpr` nodes** (see 2.6)
5. ✅ Implement `RedNode` for position queries
6. ✅ Provide `green_to_term()` conversion to maintain backward compatibility (note: `ParenExpr` maps to its inner expression in the semantic `Term`)
7. ✅ Add green tree tests (structure, positions, backward compatibility)
8. ⏳ Wire `parse_green` into primary `parse()` / `parse_tree()` path
9. ⏳ Use `RedNode` in production position queries
10. ⏳ Update docs and verify API compatibility

**Exit criteria:**
- ✅ Green tree correctly represents all parsed programs
- ✅ `ParenExpr` nodes are present for all parenthesized expressions
- ✅ Red node positions match current `TermNode` positions for all test cases
- ⏳ Structural sharing verified: unchanged subtrees are pointer-equal (value-equal verified; pointer sharing requires Phase 4 reuse cursor)
- ✅ CST distinguishes `x` from `(x)` from `((x))`
- ⏳ No performance regression on current benchmarks (benchmarks not yet run)
- ✅ All existing semantic tests pass through compatibility layer (195/195)

---

## Phase 3: Integrated Error Recovery

**Goal:** The parser continues past errors, producing a tree with error nodes interspersed among correctly parsed nodes. Multiple errors in a single parse.

### Relationship to Subtree Reuse (Phase 4)

Error recovery and subtree reuse are **independent capabilities with a soft dependency.** Grammar boundaries for reuse exist in well-formed input regardless of error recovery — every call to `parse_atom()`, `parse_application()`, `parse_expression()` IS a grammar boundary. Subtree reuse can be implemented and validated on well-formed inputs without error recovery.

Error recovery becomes necessary for reuse to work on **malformed** inputs: without it, a parse error means no old tree exists, so there is nothing to reuse on the next edit. In practice, most edits in an editor are to valid code that produces valid code, so Phase 4 can deliver value before Phase 3 is complete.

**Recommended approach:** Implement Phase 4 (subtree reuse on valid input) in parallel with Phase 3 (error recovery). Then integrate them: error recovery produces partial trees that subtree reuse can operate on for malformed inputs.

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
  guard p.current_token_text() == first_token_text(candidate)

  // Check 5: Does the trailing context match? (See 4.2.1)
  let next_token_after = token_at_offset(p.token_buffer, node_end)
  guard next_token_after == old_token_after(cursor, candidate)

  // Reuse! Skip the parser ahead by this node's width
  p.advance_by(candidate.text_len)
  cursor.advance_past(candidate)
  Some(candidate)
}
```

#### 4.2.1 Why Trailing Context Matters

The leading-token check alone is **not sufficient** for correctness. A node can have the same leading token and kind but require a different parse due to changes in the tokens that follow it.

**Concrete example:**

```
Old source:  "x + y z"
Parsed as:   Bop(Plus, Var("x"), App(Var("y"), Var("z")))

Edit: change space between y and z to " - "

New source:  "x + y - z"
Should be:   Bop(Minus, Bop(Plus, Var("x"), Var("y")), Var("z"))
```

The old `App(Var("y"), Var("z"))` subtree starts at `y`, has leading token `y`, kind `AppExpr`, and its span `[4, 7)` does not overlap the edit (which is at position 5, replacing one byte). The leading-token check passes. The damage-range check may pass depending on how tight the damage boundary is. But reuse would be incorrect — `y` should now be a standalone `VarRef`, not the left side of an `App`, because the `z` that followed it is no longer an application argument but a separate operand of `-`.

The trailing-context check catches this: the token after the old `App` node was `EOF` (or end of input), but the token after position 7 in the new source is `-`. The mismatch rejects the reuse.

**Rule:** A node's parse can depend on what comes after it (the "follow set" in grammar terms). Left-associative application in lambda calculus is particularly sensitive: `parse_application` greedily consumes atoms as long as the next token could start an atom. If the next token changes from atom-starting to non-atom-starting (or vice versa), the old subtree's span is wrong.

**Check 5 is conservative but correct:** If the token immediately after the old node's span is different in the new source, reject the reuse. This may reject some valid reuses (false negatives), but it never accepts an invalid reuse (no false positives).

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

### 4.6 Performance Analysis

For a localized edit (changing a single token) in a file with N tokens:
- **Current:** O(N) tokenization + O(N) parsing = O(N) total
- **After Phase 1:** O(1) tokenization + O(N) parsing = O(N) total
- **After Phase 4:** O(1) tokenization + O(depth) tree construction

The improvement comes from reusing subtrees off the edit path and only constructing new nodes along the path from root to the edited leaf.

**Complexity depends on tree shape, not just tree size:**

Lambda calculus trees are **not balanced**. Left-associative application and nested lambdas produce left-leaning spines:

```
f a b c d e    →  App(App(App(App(App(f, a), b), c), d), e)
                  depth = O(N)

\a.\b.\c.\d.x  →  Lam(a, Lam(b, Lam(c, Lam(d, x))))
                  depth = O(N)
```

For these structures, editing the rightmost leaf still requires O(N) new nodes because every ancestor is on the spine. **Subtree reuse helps with siblings (the `a`, `b`, `c` atoms are reused), but the spine itself must be rebuilt.**

| Tree Shape | Depth | Edit Cost | Example |
|-----------|-------|-----------|---------|
| Application chain | O(N) | O(N) | `f a b c d e` |
| Nested lambdas | O(N) | O(N) | `\a.\b.\c.\d.\e.x` |
| Binary expression chain | O(N) | O(N) | `a + b + c + d` |
| Multi-definition file (Phase 5) | O(K) | O(K) | `let x = ... let y = ...` |

Where K = size of the edited definition, N = total file size.

**The real win from subtree reuse is not asymptotic for single expressions** — it is that editing one top-level definition (after Phase 5 adds let bindings) does not require re-parsing other definitions. For a file with M definitions of average size K, editing one definition costs O(K) instead of O(M * K). This is the practical case where incremental parsing matters.

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

## Phase 6: CRDT Exploration (Research)

**Goal:** Investigate how the incremental parser integrates with CRDT-based collaborative editing. This phase is exploratory — the CRDT design space is large and the right approach depends on decisions not yet made.

**Status: This is a research phase, not an implementation plan.** The existing `crdt_integration.mbt` provides AST↔CRDTNode conversion functions but contains no actual CRDT logic (no conflict resolution, no causal ordering, no concurrent edit handling). Building genuine CRDT integration requires answering fundamental design questions first.

### 6.1 Open Design Questions

**Q1: What layer does the CRDT operate on?**

| Layer | CRDT Type | Pros | Cons |
|-------|-----------|------|------|
| Characters | RGA / Fugue | Well-studied, text CRDTs work | No structural awareness; parser must re-parse after every merge |
| Tokens | Custom sequence CRDT | Preserves token boundaries | Token identity is fragile (edits create/destroy tokens) |
| AST nodes | Tree CRDT (e.g., MRDT) | Structural edits are first-class | Complex; AST changes are derived from text changes, not direct |
| Source text + parse on merge | Text CRDT + incremental parser | Simplest; leverages Phases 1-4 | No semantic merge (text conflicts may produce invalid syntax) |

The simplest viable approach is likely **text-level CRDT + incremental parser on merge**. Each peer maintains source text via a text CRDT (e.g., Fugue or RGA). After merging remote operations into the local text, the incremental parser re-parses the affected region. This requires no custom tree CRDT and fully leverages the incremental parsing infrastructure.

**Q2: What does "tree diff" mean for green trees?**

The green tree enables efficient structural comparison via pointer equality (unchanged subtrees are the same object). A diff algorithm can skip pointer-equal subtrees in O(1). But the output of a diff is a sequence of tree edits (insert node, delete node, replace node), and it's not yet clear whether these map cleanly to CRDT operations or whether they're even needed. If using a text-level CRDT, tree diffs are informational (for UI updates), not operational.

**Q3: What convergence guarantees are needed?**

- **Text convergence:** All peers see the same source text after merging all operations. This is provided by the text CRDT.
- **Parse convergence:** All peers produce the same parse tree for the same source text. This is provided by the parser being deterministic.
- **Semantic convergence:** Concurrent edits to different declarations don't interfere. This is provided by text convergence + incremental parsing (editing one let binding doesn't affect others).

### 6.2 Recommended Starting Point

```
Peer A                          Peer B
  |                               |
  | local edit                    | local edit
  v                               v
Text CRDT  ---sync operations-->  Text CRDT
  |                               |
  | merged text                   | merged text
  v                               v
Incremental Parser              Incremental Parser
  |                               |
  | green tree                    | green tree (identical)
  v                               v
UI update                       UI update
```

This avoids the complexity of tree CRDTs entirely. The incremental parser provides the "structure-aware" layer — it knows which subtrees changed and can update the UI efficiently. The CRDT handles text convergence, which is well-solved.

### 6.3 What to Build

1. **Green tree diff utility:** Given old and new green trees, produce a list of changed subtrees with their positions. Uses pointer equality for O(1) skip of unchanged subtrees. This is useful for UI updates regardless of CRDT choice.

2. **Text CRDT adapter:** Translate CRDT text operations (insert character at position, delete range) into the `Edit` type that the incremental parser accepts. This is a thin mapping layer.

3. **Integration test harness:** Simulate two peers making concurrent edits. Verify that after sync, both peers have identical source text and identical parse trees.

### 6.4 What NOT to Build (Yet)

- Custom tree CRDT for AST nodes (premature — text CRDT may be sufficient)
- Semantic merge (resolving conflicts at the declaration level — research problem)
- Real-time operational transformation (CRDT handles this at the text layer)

**Exit criteria for this phase:**
- Design document answering Q1-Q3 with evidence from prototyping
- Green tree diff utility implemented and tested
- Text CRDT adapter producing valid `Edit` objects
- Integration test: two simulated peers converge on same parse tree
- Clear recommendation on whether to pursue tree-level CRDT or stay with text-level

---

## Phase Summary and Dependencies

```
Phase 0: Reckoning          (no dependencies - cleanup)
    |
    +------ Phase 1: Incremental Lexer  (depends on Phase 0)
    |
    +------ Phase 2: Green Tree         (depends on Phase 0, parallel with Phase 1)
                |
                +------ Phase 3: Error Recovery     (depends on Phase 2)
                |
                +------ Phase 4: Subtree Reuse      (depends on Phase 1, 2)
                |
                +------ Phase 3 + 4 combined: reuse on malformed input
                |
                +------ Phase 5: Grammar Expansion  (depends on Phase 2, 3)
                |
                +------ Phase 6: CRDT Exploration   (depends on Phase 2, 4)
```

Phases 1 and 2 can proceed in parallel after Phase 0.
Phases 3 and 4 can proceed in parallel after Phase 2 (Phase 4 also needs Phase 1).
Phase 4 works on well-formed input without Phase 3. Full incremental reuse on malformed input requires both.
Phases 5 and 6 can proceed in parallel after their dependencies.

---

## Cross-Cutting Concern: Incremental Correctness Testing

The fundamental correctness property — **for any edit, incremental parse produces a tree structurally identical to a full reparse** — must be continuously verified across all phases. This is not a Phase 4 concern alone; it applies from the moment the first incremental operation is introduced (Phase 1's incremental lexer).

### Differential Testing Oracle

Every incremental operation must be shadow-verified against its non-incremental equivalent:

```
fn verify_incremental_correctness(
  source : String,
  edit : Edit,
  new_source : String,
) -> Bool {
  // Path 1: Incremental
  let parser = IncrementalParser::new(source)
  parser.parse()
  let incremental_result = parser.edit(edit, new_source)

  // Path 2: Full reparse (oracle)
  let full_result = parse(new_source)

  // Compare structure, ignoring node IDs and other metadata
  structurally_equal(incremental_result, full_result)
}
```

This oracle runs in CI on every commit. It is not optional.

### Property-Based Fuzzing

Use QuickCheck (already a dependency) to generate random test cases:

1. **Random source generation:** Generate random well-formed lambda calculus expressions. The grammar is small enough that a recursive generator with size bounds produces good coverage.

2. **Random edit generation:** For a given source string, generate random edits: insertions, deletions, and replacements at random positions with random content.

3. **Edit sequence testing:** Apply sequences of 10-100 random edits, verifying the correctness invariant after each one. This catches state accumulation bugs that single-edit tests miss.

4. **Adversarial edits:** Specifically target edit boundaries: edits that split tokens, create keywords from identifiers (`i` → `if`), remove parentheses, insert at position 0, append at end, delete everything, etc.

### Phase-Specific Testing Requirements

| Phase | What to verify | Oracle |
|-------|---------------|--------|
| Phase 1 (Incremental Lexer) | Incremental tokenization == full tokenization | `incremental_lex(edit) == tokenize(new_source)` |
| Phase 2 (Green Tree) | Green tree → Term matches old parser's Term | `green_to_term(green_parse(s)) == parse(s)` |
| Phase 3 (Error Recovery) | Parser terminates on all inputs; valid inputs unchanged | Fuzzing with random bytes; regression suite |
| Phase 4 (Subtree Reuse) | Incremental parse == full reparse | Full differential oracle |
| Phase 5 (Grammar Expansion) | New constructs parse correctly; old constructs unchanged | Existing test suite + new construct tests |

### Regression Suite

Every bug found during development becomes a permanent regression test. The test captures:
- The source before the edit
- The edit
- The expected tree after the edit
- A comment explaining what went wrong

This suite grows monotonically — tests are never removed.

### CI Integration

The full test suite (including property-based fuzzing with 10,000+ random cases) runs on every push. Benchmarks run on tagged commits to detect performance regressions. The differential oracle is always enabled, even in release builds during testing.

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
- **Trailing context sensitivity:** A node's parse can depend on what follows it. Left-associative application is particularly sensitive — `parse_application` greedily consumes atoms based on the next token. The trailing-context check (section 4.2.1) addresses this, but the exact boundary conditions need careful testing.
- **Reuse cursor synchronization:** Keeping the cursor aligned with the parser requires careful bookkeeping. If the cursor falls out of sync (e.g., after error recovery skips tokens), all subsequent reuse checks may fail silently.
- **Edge cases at edit boundaries:** Edits that create or destroy token boundaries (e.g., inserting a space to split an identifier) stress both the incremental lexer and the reuse protocol simultaneously.
- **Tree shape limits gains:** Lambda calculus produces left-leaning spines with O(N) depth, so the spine must always be rebuilt. The real win comes after Phase 5 adds let bindings.

Mitigated by: The differential testing oracle (see Cross-Cutting Concern section) catches all correctness bugs. Property-based fuzzing with random edits runs on every commit. Reuse can be conservatively disabled (fall back to full reparse) if any check is uncertain — correctness is never sacrificed for performance.

### Milestone 6: Grammar Expansion (Phase 5)
**Confidence: High**

Adding let bindings and type annotations to a recursive descent parser is straightforward. The green tree architecture supports new node kinds naturally.

### Milestone 7: CRDT Exploration (Phase 6)
**Confidence: Low-Medium (research phase)**

This is explicitly exploratory. The most likely outcome is "text-level CRDT + incremental parser on merge," which is architecturally simple but requires answering design questions about convergence guarantees and the value of tree-level awareness. The green tree diff utility is the concrete deliverable; the CRDT architecture decision is the intellectual deliverable.

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
