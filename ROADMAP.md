# Roadmap: Stabilized Incremental Parser

**Created:** 2026-02-01
**Updated:** 2026-02-28
**Status:** Active — Phases 0-7 complete; next: NodeInterner, Typed SyntaxNode views, or Grammar Expansion
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

6. **Test suite** - 272 tests passing, including property-based tests and Phase 3 fuzz tests. Good coverage.

### What Does Not Work (Architectural Gaps)

**Phase 0 (completed 2026-02-01) removed the dead cache infrastructure.** `TokenCache`, `ParseCache`, and `RecoveringParser` have been deleted. The incremental parser now honestly does:
1. Track damage (works)
2. Check whole-tree reuse (works when damage is outside tree bounds)
3. Full reparse (fallback for all other cases)

### Error Recovery ✅ (Phase 3 Complete)

**Phase 3 (completed 2026-02-03) implemented integrated error recovery.** The parser now:
- Uses synchronization points (`RightParen`, `Then`, `Else`, `EOF`) for recovery
- Produces partial trees with `ErrorNode`/`ErrorToken` interspersed among valid nodes
- Reports multiple errors per parse (up to `max_errors = 50`)
- Continues parsing after errors, recovering at grammar boundaries
- Terminates on any input (fuzz-tested with random token sequences)

### CRDT Integration is Conceptual

`crdt_integration.mbt` provides `ast_to_crdt()` and `crdt_to_source()` conversion functions. This is a mapping layer, not a CRDT integration. There is no:
- Conflict resolution
- Concurrent edit handling
- Operation-based synchronization
- Actual CRDT data structure

### Summary

| Component | Status |
|-----------|--------|
| Recursive descent parser | **Correct** — `parse()`, `parse_tree()`, `parse_cst()` paths |
| Lexer | **Correct** — trivia-inclusive; emits `Whitespace` tokens |
| Damage tracking | **Correct** — Wagner-Graham algorithm |
| Position adjustment | **Correct** — width-based via `SyntaxNode` (no absolute-position bug) |
| ~~Token cache~~ | **Deleted** (Phase 0) |
| ~~Parse cache~~ | **Deleted** (Phase 0) |
| Incremental lexer | **Complete** (Phase 1) — `TokenBuffer` splice-based re-lex |
| Green tree / CST | **Complete** (Phase 2) — `CstNode`, `SyntaxNode`, `EventBuffer`, `seam/` package |
| Error recovery | **Complete** (Phase 3) — sync-point recovery, `ErrorNode`, diagnostics |
| Subtree reuse | **Complete** (Phase 4) — `ReuseCursor` with 4-condition protocol |
| Generic parser framework | **Complete** (Phase 5) — `ParserContext[T,K]`, `LanguageSpec`, `parse_with` |
| Generic incremental reuse | **Complete** (Phase 6) — `ReuseCursor[T,K]` in `src/core/`, `node()`/`wrap_at()` |
| Reactive pipeline | **Complete** (Phase 7) — `ParserDb`: `Signal`→`Memo[TokenStage]`→`Memo[CstStage]` |
| SyntaxNode API | **Complete** — `SyntaxToken`, `SyntaxElement`, `all_children`, `find_at`, `tight_span` |
| `cst` field privacy | **Complete** — `.cst` is private; all callers use `SyntaxNode` methods |
| CRDT integration | **Conversion functions** — `ast_to_crdt`, `crdt_to_source`; no conflict logic |
| NodeInterner | **Planned** — design doc at `docs/plans/2026-02-25-node-interner-design.md` |
| Typed SyntaxNode views | **Planned** — Phase 3 of SyntaxNode-first layer design |

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

Removed all dead cache infrastructure (`TokenCache`, `ParseCache`, `RecoveringParser` — ~581 lines).
Parser now honestly does: damage tracking → whole-tree reuse check → full reparse.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 1: Incremental Lexer ✅ COMPLETE (2026-02-02)

Splice-based `TokenBuffer` re-lexes only the damaged region (typically ~50 bytes for a 1-char edit
in a 10KB file) and splices the result into the existing token array. Implemented in `src/lexer/token_buffer.mbt`.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 2: Green Tree (Immutable CST) ✅ COMPLETE (2026-02-19)

`CstNode` (position-independent, content-addressed, structurally shareable) + `SyntaxNode` (ephemeral
positioned facade) + `EventBuffer` (flat event stream → tree) + `seam/` package. Unchanged subtrees
are the same pointer, not copies.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 3: Integrated Error Recovery ✅ COMPLETE (2026-02-03)

Sync-point recovery (`RightParen`, `Then`, `Else`, `EOF`). Produces partial trees with
`ErrorNode`/`ErrorToken` interspersed among valid nodes. Reports up to 50 errors per parse.
Fuzz-tested for termination on any token sequence.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 4: Checkpoint-Based Subtree Reuse ✅ COMPLETE (2026-02-03)

`ReuseCursor` with 4-condition reuse protocol: kind match + leading token context + trailing
token context + no damage overlap. Trailing context check is essential — a node's parse can
depend on what follows it. O(depth) per lookup via stateful frame stack.
[Full notes →](docs/archive/completed-phases/phases-0-4.md)

---

## Phase 5: Generic Parser Framework ✅ COMPLETE (2026-02-23)

> **Note:** The originally planned "Phase 5: Grammar Expansion" was superseded by this work.
> The original grammar expansion plan is preserved below as "Phase 5 (original plan)".

**Goal:** Extract a reusable `ParserContext[T, K]` API so any MoonBit project can define a parser against the green tree / error recovery / incremental infrastructure.

**What was built:**
- `src/core/` package: `TokenInfo[T]`, `Diagnostic[T]`, `LanguageSpec[T, K]`, `ParserContext[T, K]`
- `ParserContext::new` (array-based) and `ParserContext::new_indexed` (closure-based, zero-copy)
- Full method surface: `peek`, `at`, `at_eof`, `emit_token`, `start_node`, `finish_node`, `mark`, `start_at`, `error`, `bump_error`, `emit_zero_width`, `emit_error_placeholder`, `flush_trivia`
- `parse_with[T, K]` top-level entry point
- `Diagnostic[T]` with `got_token : T` (captures offending token at parse time)
- Lambda parser migrated to `ParserContext` as reference implementation
- Trivia-inclusive lexer integration: whitespace in token stream, `flush_trivia()` before grammar return
- 367 total tests passing; 56 benchmarks passing

---

## Phase 6: Generic Incremental Reuse ✅ COMPLETE (2026-02-24)

**Goal:** Wire `ReuseCursor[T, K]` from `src/core/` into `ParserContext` via `node()`/`wrap_at()` combinators so incremental subtree reuse fires transparently for any grammar.

**What was built:**
- `ReuseCursor[T, K]` generic struct in `src/core/` with `collect_old_tokens`, `try_reuse`, `seek_node_at`, `advance_past`
- `ParserContext` gains `reuse_cursor`, `reuse_count`, `set_reuse_cursor`, `set_reuse_diagnostics`
- `node(kind, body)` combinator: skips `body` closure on reuse hit (O(edit) skip)
- `wrap_at(mark, kind, body)` combinator: retroactive wrapping; inner `node()` calls still reuse
- Lambda grammar migrated: `parse_atom` uses `ctx.node()`, binary/app rules use `ctx.wrap_at()`
- `run_parse_incremental` helper wires cursor + diagnostics
- Old lambda-specific `ReuseCursor` removed from `src/parser/` (~946 lines deleted)
- `prev_diagnostics?` parameter for diagnostic replay on reused subtrees
- 372 total tests passing; 59 benchmarks passing (Phase 3 cursor benchmarks added)

---

## Phase 7: Reactive Pipeline (ParserDb) ✅ COMPLETE (2026-02-25)

**Goal:** Build `ParserDb`, a `Signal`/`Memo`-backed Salsa-style incremental pipeline using `CstNode` value equality for automatic stage backdating.

**Architecture:** `source_text : Signal[String]` → `tokens : Memo[TokenStage]` → `cst : Memo[CstStage]`

**What was built:**
- `dowdiness/incr` added as git submodule dependency
- `TokenStage` enum and `CstStage` struct, both `Eq`-derived for backdating
- `ParserDb::new()`, `set_source()`, `cst()`, `diagnostics()`, `term()` public API
- Option B error routing: tokenization failure → `AstNode::error(...)` (consistent with `IncrementalParser`)
- `diagnostics()` returns `.copy()` to prevent mutation of memoized backing array
- 343 total tests passing; 59 benchmarks passing

---

## SyntaxNode-First Layer ✅ COMPLETE (2026-02-25)

**Goal:** Make `SyntaxNode` the primary interface for all tree operations; eliminate direct `.cst` field access from callers.

**Phase 1 — Extend `SyntaxNode` API (complete):**
- `SyntaxToken` positioned leaf view; `SyntaxElement` union type
- `all_children()`, `tokens()`, `find_token()`, `tokens_of_kind()`, `tight_span()`, `find_at()`
- `Show` and `Debug` impls for `SyntaxNode` and `SyntaxToken`

**Phase 2 — SyntaxNode-first callers (complete):**
- `cst_convert.mbt` replaced free functions with `SyntaxNode` methods
- `IncrementalParser` stores `SyntaxNode?` instead of `CstNode?`
- `.cst` field made private — abstraction boundary enforced
- `parse_with_error_recovery_tokens` removed (no callers; was broken)

**Phase 3 — Typed views (planned):**
- `LambdaExpr(SyntaxNode)`, `AppExpr(SyntaxNode)` typed wrappers
- `AstNode` becomes JSON-serialization-only

---

## Phase 5 (original plan): Grammar Expansion and CST Maturity

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

2. **Text CRDT adapter:** Translate CRDT text operations into the `Edit` type that the incremental parser accepts. The concrete pipeline is:

   ```
   TextDelta (Retain | Insert | Delete)   ← Loro/Quill Delta format
     ↓ .to_edits()
   Edit { start, old_len, new_len }       ← lengths, not endpoints
     ↓ implements
   pub trait Editable                     ← IncrementalParser accepts T : Editable
   ```

   `Edit` now stores lengths (`old_len`, `new_len`) as primitive fields, which makes this conversion direct: `Delete(n)` maps to `old_len = n`, `Insert(s)` maps to `new_len = s.length()`, `Retain(n)` advances the cursor by `n`. No subtraction needed. `Editable` is already implemented for `Edit`; any future adapter type (e.g., a lazy `PendingEdit` that defers string allocation) can implement the same trait without touching `IncrementalParser`.

3. **Integration test harness:** Simulate two peers making concurrent edits. Verify that after sync, both peers have identical source text and identical parse trees.

### 6.4 What NOT to Build (Yet)

- Custom tree CRDT for AST nodes (premature — text CRDT may be sufficient)
- Semantic merge (resolving conflicts at the declaration level — research problem)
- Real-time operational transformation (CRDT handles this at the text layer)

**Exit criteria for this phase:**
- Design document answering Q1-Q3 with evidence from prototyping
- Green tree diff utility implemented and tested
- `TextDelta.to_edits()` producing values that implement `Editable` ✅ trait defined and `Edit` impl complete
- Integration test: two simulated peers converge on same parse tree
- Clear recommendation on whether to pursue tree-level CRDT or stay with text-level

---

## Phase Summary and Dependencies

```
Phase 0: Reckoning                  ✅ COMPLETE (2026-02-01)
    |
    +------ Phase 1: Incremental Lexer      ✅ COMPLETE (2026-02-02)
    |
    +------ Phase 2: Green Tree / seam/     ✅ COMPLETE (2026-02-19)
                |
                +------ Phase 3: Error Recovery         ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 4: Subtree Reuse          ✅ COMPLETE (2026-02-03)
                |
                +------ Phase 5: Generic Parser Ctx     ✅ COMPLETE (2026-02-23)
                |           |
                |           +-- Phase 6: Generic Reuse  ✅ COMPLETE (2026-02-24)
                |
                +------ SyntaxNode-First Layer          ✅ COMPLETE (2026-02-25)
                |           Phase 1: SyntaxNode API
                |           Phase 2: .cst private
                |           Phase 3: Typed views        ← PLANNED
                |
                +------ Phase 7: ParserDb (reactive)    ✅ COMPLETE (2026-02-25)
                |
                +------ NodeInterner                    ← PLANNED
                |
                +------ Grammar Expansion               ← PLANNED (original Phase 5)
                |
                +------ CRDT Exploration               ← PLANNED (original Phase 6)
```

Phases 0-7 and the SyntaxNode-First Layer (Phase 1+2) are complete.
Next candidates: NodeInterner, Typed SyntaxNode views, ParserDb benchmarks, Grammar Expansion.

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

| Phase | What to verify | Oracle | Status |
|-------|---------------|--------|--------|
| Phase 1 (Incremental Lexer) | Incremental tokenization == full tokenization | `incremental_lex(edit) == tokenize(new_source)` | ✅ Verified |
| Phase 2 (Green Tree) | Green tree → Term matches old parser's Term | `green_to_term(green_parse(s)) == parse(s)` | ✅ Verified |
| Phase 3 (Error Recovery) | Parser terminates on all inputs; valid inputs unchanged | Fuzzing with random tokens; regression suite | ✅ Verified |
| Phase 4 (Subtree Reuse) | Incremental parse == full reparse | Full differential oracle | ✅ Verified |
| Phase 5 (Grammar Expansion) | New constructs parse correctly; old constructs unchanged | Existing test suite + new construct tests | Pending |

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

### Milestone 2: Incremental Lexer (Phase 1) ✅ COMPLETE
**Confidence: Certain (completed)**

Incremental lexing implemented with splice-based TokenBuffer updates. Conservative boundary expansion handles keyword formation edge cases. Benchmarked on 110-token input: incremental update is 1.3-1.7x faster than full re-tokenize, with all operations under 3 us. Property tests verify correctness (incremental lex == full lex).

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

**Findings (correctness/edge cases):**
- Trailing-context check enforces follow-token equality (Option B): the first non-whitespace token after the node's end offset must be identical in both old and new token streams. Prevents identifier/integer boundary merges.
- Leading token match for integers requires both numeric value equality and canonical text equality (e.g., `007` does not match `7`).
- Reuse is conservative around leading whitespace because reuse is anchored to the first non-whitespace token offset, reducing reuse on whitespace-only edits.
- Adjacent damage is treated as unsafe (strict inequality), which prevents false reuse for grammar-sensitive boundaries like application.

**Findings (performance profiling):**
- Hot path for root-invalidating edits was `find_node_at_offset` recursion (many
  calls, zero reuse hits), causing search overhead to dominate when reuse is
  unlikely.
- **Implemented optimizations:**
  1. **Fast path skip:** When byte offset is within damaged range [start, end),
     skip tree search immediately. For root-invalidating edits, this avoids all
     `find_node_at_offset` calls (measured: `fast_path_skips: 45`,
     `find_node_calls: 0`).
  2. **Stateful cursor:** `ReuseCursor` maintains a stack of `CursorFrame`s
     tracking position in the tree. Sequential lookups are O(depth) instead of
     O(tree). Measured: 4 lookups in 10 total steps (avg 2.5 steps/lookup).
- **Why timing benchmarks show minimal change:** Lambda calculus trees are
  small (~15-30 tokens), and Wagner-Graham damage expansion causes any edit to
  expand damage to the entire root for single-expression files. The real win
  comes with Phase 5's `let` bindings creating independent subtrees.

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

### CRDT and Collaborative Editing
- Gentle et al. (2024) - [eg-walker: Mergeable Tree Structures](https://arxiv.org/abs/2409.14252) - The algorithm this project implements; uses length-based edit representation throughout
- [diamond-types](https://github.com/josephg/diamond-types) - Rust reference implementation of eg-walker; `PositionalComponent { Ins { len }, Del(len) }` stores lengths not endpoints
- [Loro](https://loro.dev) - Production CRDT library; `TextDelta (Retain | Insert | Delete)` follows Quill Delta format with lengths as primitives; directly motivates the `Edit { start, old_len, new_len }` design
- [Quill Delta format](https://quilljs.com/docs/delta/) - Retain/Insert/Delete with lengths; the industry-standard representation for collaborative text operations

### MoonBit
- [MoonBit Language Reference](https://www.moonbitlang.com/docs/syntax)
- [MoonBit Core Libraries](https://mooncakes.io/docs/#/moonbitlang/core/)
