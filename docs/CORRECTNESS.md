# Correctness: Incremental Parser

This document defines what correctness means for the incremental parser, how it
is achieved, and what is continuously verified.

## Correctness Goals

### Primary Invariant

For any edit, the incremental parse must produce a tree structurally identical
to a full reparse of the edited source.

In other words:

incremental_parse(source, edit, new_source) == full_parse(new_source)

Structural identity ignores node IDs and other incidental metadata. The
structure, kinds, and token boundaries must match.

### Secondary Invariants

- Tokenization correctness: incremental lexing must match full lexing.
- Error recovery determinism: for the same source, recovery produces the same
  green tree and diagnostic sequence on each run.
- Termination: all inputs (including malformed ones) must terminate without
  panic, producing a tree with ErrorNode/ErrorToken where needed.

## How Correctness Is Achieved

### 1) Conservative Reuse Protocol

Subtree reuse is permitted only when multiple checks succeed:

- Node kind matches the expected kind at the parser checkpoint.
- Node is outside the damaged range (strict inequality at boundaries).
- Leading token kind/text matches the current token stream.
- Trailing context is intended to be validated (Option B: follow-token match).

If any check is uncertain, reuse is skipped and a fresh parse is performed.
Correctness is never traded for reuse.

### 2) Damage Tracking

Edits produce a damaged range using the Wagner-Graham algorithm. Reuse is
disallowed for any subtree overlapping this range, so rebuilt regions are
always parsed from the new source.

### 3) Incremental Lexer Oracle

TokenBuffer updates are verified against full lexing. Token boundaries and
TokenInfo ranges must match exactly. This makes the incremental parser's token
stream a reliable source of truth for both parsing and reuse checks.

### 4) Error Recovery Is Part of Parsing

The parser does not raise on syntax errors. Instead it inserts ErrorNode and
ErrorToken while continuing to parse. This ensures incremental parsing always
has a well-defined output tree, even for incomplete or malformed input.

### 5) Green Tree Identity

Green tree nodes are immutable. Reused subtrees are literally the same nodes,
not copies. This provides a strong correctness foundation for reuse and for
structural comparisons in tests.

## Continuous Verification

### Differential Oracle

Every incremental edit is compared against a full reparse. This is the main
correctness oracle and is expected to run in CI.

### Property-Based Fuzzing

Random edits and random inputs are used to validate:

- Incremental vs full parse identity
- Termination under malformed input
- Error recovery stability

### Regression Tests

Any bug found becomes a permanent regression test. The test captures:

- Source before the edit
- Edit specification
- Expected tree after edit

## Current Edge-Case Findings

These are documented to keep the correctness story honest:

- Trailing-context checks are currently permissive; follow-token comparison is
  the next hardening step (Option B).
- Leading token match for integers currently ignores literal text. This is safe
  under correct damage ranges but weakens the token-level invariant.
- Reuse is conservative around leading whitespace, reducing reuse on
  whitespace-only edits but preserving correctness.
- Adjacent damage is treated as unsafe, which avoids false reuse at
  grammar-sensitive boundaries (application).

## Scope of Correctness

Correctness here is strictly about parse tree equivalence between incremental
and full parsing. It does not guarantee:

- Any particular reuse rate or performance improvement
- Semantic equivalence beyond the syntax tree
- Conflict resolution for concurrent edits (CRDT is out of scope)

## Future Work

- Option B: Follow-token comparison for trailing context checks
- Semantics-aware follow-set checks for projectional/live editors
