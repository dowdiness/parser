# `seam` Publish-Readiness Plan (Standalone Module)

**Date:** 2026-02-22
**Updated:** 2026-02-24
**Status:** In Progress — Phase 0 not started; Phases 1–2 partially complete; Phases 3–6 not started

## Goal

Make `seam` (the standalone CST/syntax-tree infrastructure, currently at
`src/green-tree/`) publish-ready as an independent MoonBit module: hardened API,
complete tests, standalone module packaging, and documentation sufficient for a
first public release. Actual publishing (`v0.1.0` tag, mooncakes upload) is out
of scope for this plan.

## Scope

In scope:
- Standalone module packaging and metadata
- API hardening for `seam` core types
- Test coverage and documentation for external users
- CI and release checklist

Out of scope:
- Migration from current internal import paths
- Backward-compatibility shims
- Breaking-change mitigation for existing consumers
- Publishing to mooncakes (path-dep local use is sufficient; `v0.1.0` tag is a separate step)

## Release Target

Module name: `dowdiness/seam`
Initial version: `0.1.0` (to be tagged and published separately)

## Definition Of Done

- Module can be used via a path dependency (`"dowdiness/seam": { "path": "..." }`)
  and built in a clean project without being published to mooncakes.
- Public API is intentional, documented, and frozen.
- `moon check --target all`, `moon test`, and `moon info` pass cleanly.
- README examples are self-contained and illustrate the event-stream → tree model.
- CI gates are configured and green on the standalone module.

## Open Concerns (Track Before Release Freeze)

1. API contract granularity:
   - Freeze must be method/field-level, not just top-level symbol names, so
     `pkg.generated.mbti` diffs are meaningful review gates.
2. Deferred API decisions:
   - Resolve include/defer for `RedNode::node_at(position : Int)` and
     `GreenNode::width()` before release freeze.
   - **Current status:** neither method exists; decision unrecorded. Must be
     recorded in Task 2.2 before Phase 3.
3. Exposed implementation fields:
   - `GreenNode`, `GreenToken`, `GreenElement`, `RawKind` are declared
     `pub(all)` — every field is accessible externally. Fields `hash`,
     `token_count`, and `GreenNode::children` are incremental-parser
     implementation details that would be difficult to change post-release.
   - `EventBuffer.events : Array[ParseEvent]` is a public field; callers
     can bypass `push`/`mark`/`start_at` and corrupt the event stream.
   - Must be resolved in Task 1.1 before API freeze.
4. Scope coordination:
   - These publish concerns are not blockers for starting `incr` integration
     implementation in this repository.
   - Once Phase 3 (standalone module) is complete, the `crdt` monorepo can
     reference `seam` via a path dependency — no mooncakes publish needed.
     Path dep syntax: `"dowdiness/seam": { "path": "../seam" }` in
     `moon.mod.json`.

---

## Phase 0: Naming Alignment — ❌ Not started

Rename the three tree layers to names that are self-explanatory without
knowledge of the Roslyn/rowan tradition. Must land before Phase 1 so all
subsequent work uses the final names.

### Rationale

Current names (`green-tree`, `red-tree`, `term-tree`) come from the Roslyn
compiler (C#) and rowan (Rust). They are precise within that tradition but
opaque to newcomers. Proposed replacements:

| Current | New | Why |
|---|---|---|
| `green-tree` / `GreenNode` / `GreenToken` | `seam` module / `CstNode` / `CstToken` | "CST" signals full-fidelity trivia-preserving tree; `seam` as the module name evokes the join between old and new structure in incremental parsing |
| `red-tree` / `RedNode` | `SyntaxNode` (lives inside `seam`) | rust-analyzer convention; implies "positioned view", not a separate tree layer |
| `term-tree` / `TermNode` | `ast` / `AstNode` | Universally understood; lambda-specific semantic layer |

**Note on "ST" (syntax tree):** rejected — too ambiguous (used for both CST
and AST in different communities). `SyntaxNode` (type) inside the CST module
is the preferred convention.

### Task 0.1: Rename `green-tree` package and types — ❌ Not done

Scope:
- Rename package directory `src/green-tree/` → `src/seam/`
- Rename `GreenNode` → `CstNode`, `GreenToken` → `CstToken`,
  `GreenElement` → `CstElement`
- Update all callers in `src/core/`, `src/parser/`, `src/lexer/`,
  `src/incremental/`, `src/syntax/`, benchmarks, and tests
- Update `pkg.generated.mbti` via `moon info`

Acceptance criteria:
- `moon check` and `moon test` pass with 0 regressions
- no remaining references to the old type names in source or docs

### Task 0.2: Rename `red-tree` types — ❌ Not done

Scope:
- Rename `RedNode` → `SyntaxNode` within the CST package (or a new `syntax`
  package if a clean separation is preferred)
- Update all callers

Acceptance criteria:
- `moon check` and `moon test` pass with 0 regressions

### Task 0.3: Rename `term-tree` to `ast` — ❌ Not done

Scope:
- Rename package `src/term-tree/` (if it exists as a directory) or the
  relevant source files
- Rename `TermNode` → `AstNode` and related types
- Update all callers

Acceptance criteria:
- `moon check` and `moon test` pass with 0 regressions

---

## Phase 1: API Hardening — ⚠️ Partial

### Task 1.1: Visibility and invariants audit — ❌ Not done

Audit items:
- mutable/public fields that should be private or method-based
- error messages for invalid state transitions (`EventBuffer`, `build_tree`)
- stable semantics for equality/hash behavior

**Current state:**
- `GreenNode`, `GreenToken`, `GreenElement`, `RawKind` are all `pub(all)` —
  implementation fields (`hash`, `token_count`, `children`) are exposed.
- `EventBuffer.events` is a plain public field; the raw array is accessible
  without going through `push`/`mark`/`start_at`.
- `GreenToken::Eq` and `GreenToken::Hash` use the cached `hash` field; this
  behavior is implemented but not documented as a stability guarantee.
- `RawKind::inner` is `#deprecated` — good, no action needed.

**Remaining work:**
- Decide which fields to make private (breaking change — must happen before
  standalone module is published).
- Add invariant docs to each public type: what the cached `hash` represents,
  what `token_count` counts, what `EventBuffer` balancing requires.
- Document `Eq`/`Hash` fast-path semantics as a stability guarantee.

Acceptance criteria:
- each public type/method has concise docs for invariants
- trait impl behavior (`Eq`, `Hash`) is documented and tested

### Task 1.2: Rowan-model documentation — ❌ Not done

Document mapping:
- `RawKind` ~ rowan raw kind
- green tree vs red tree responsibilities
- event stream to tree construction model

**Current state:** no Rowan-model documentation exists anywhere in the
codebase. External users cannot understand the event-stream → tree model
without reading the source.

Acceptance criteria:
- section included in README
- examples illustrate the model directly

---

## Phase 2: Contract And API Freeze — ❌ Not started

### Task 2.1: Freeze public API surface — ❌ Not done

Target public symbols (all present in `pkg.generated.mbti` as of 2026-02-24):
- `RawKind` ✅ (exists)
- `GreenToken` ✅ (exists)
- `GreenElement` ✅ (exists)
- `GreenNode` ✅ (exists)
- `RedNode` ✅ (exists)
- `ParseEvent` ✅ (exists)
- `EventBuffer` ✅ (exists)
- `build_tree` ✅ (exists)
- `build_tree_interned` ✅ (bonus: token deduplication for incremental use)
- `Interner` ✅ (bonus: required by `build_tree_interned`)
- hash utilities (`combine_hash`, `string_hash`) ✅ (exist)

**Remaining work:**
- Resolve Task 1.1 field visibility before freezing — the surface area of
  `pub(all)` structs is currently larger than intended.
- Write an explicit API contract document (or section in this plan) listing
  every public symbol, its invariants, and stability level.
- Verify `pkg.generated.mbti` matches contract exactly after freeze.

Acceptance criteria:
- API contract section in this plan (or separate `docs/api-contract.md`)
- explicit notes for any deferred API
- `pkg.generated.mbti` matches contract exactly
- no accidental exports remain

### Task 2.2: Decide deferred vs included APIs — ❌ Not done

Decide now:
- Include or defer `RedNode::node_at(position : Int)`
- Include or defer `GreenNode::width()` alias for `text_len`

**Current state:** neither method exists; no decision has been recorded.

Acceptance criteria:
- decision recorded in docs
- implementation and tests match the decision

---

## Phase 3: Standalone Module Bootstrap — ❌ Not started

**Current state:** `seam` (currently `green-tree`) lives at `src/green-tree/`
inside the `dowdiness/parser` module (`moon.mod.json` name = `"dowdiness/parser"`).
It cannot be added as a standalone dependency today.

### Task 3.1: Create module skeleton — ❌ Not done

Files:
- `moon.mod.json`
- `moon.pkg` (root package manifest)
- `README.mbt.md` (symlink `README.md` if desired)
- `LICENSE`
- source files under package root

Required metadata in `moon.mod.json`:
- `name: "dowdiness/seam"`
- `version: "0.1.0"`
- `repository`
- `license`
- `keywords`
- `description`

Acceptance criteria:
- module builds without project-local dependencies
- package imports are minimal and intentional

### Task 3.2: Move/copy core implementation — ❌ Not done

Source set (all present in current `src/green-tree/`, will move to `src/seam/`):
- `green_node.mbt` ✅
- `red_node.mbt` ✅
- `event.mbt` ✅
- `hash.mbt` ✅
- `interner.mbt` ✅ (not in original plan — include in standalone)

Acceptance criteria:
- behavior matches current internal `green-tree` / `seam`
- no parser/language-specific code in standalone module

---

## Phase 4: Test Completion — ⚠️ Partial

**Current state:** unit tests exist in `*_wbtest.mbt` files for green node,
red node, event buffer, hash, and interner. No panic/abort path tests and no
property-style tests exist.

### Task 4.1: Unit + panic tests — ⚠️ Partial

Required coverage:
- constructor correctness (`text_len`, hash derivation) ✅ covered
- equality/hash fast-path behavior ✅ covered (hash_test.mbt)
- event balancing invariants ✅ partially covered (event_wbtest.mbt)
- red-node offsets and traversal ✅ covered (red_node_wbtest.mbt)
- deferred/included API behavior (`node_at`, `width`) per Phase 2 ❌ pending decision

**Remaining work:**
- Add explicit panic/abort tests for:
  - `EventBuffer::start_at` on out-of-bounds mark index
  - `EventBuffer::start_at` on non-Tombstone slot
  - `build_tree` with unbalanced StartNode/FinishNode

Acceptance criteria:
- all tests pass with `moon test`
- panic/abort paths are explicitly tested

### Task 4.2: Property-style confidence checks — ❌ Not done

Suggested properties:
- deterministic structural hash for identical trees
- `build_tree` preserves concatenated text length
- red node child offsets are monotonic and contiguous

**Current state:** `moonbitlang/quickcheck` is already a dependency of the
`dowdiness/parser` module, so property tests can be added without new deps.

Acceptance criteria:
- property tests added where practical
- failures produce actionable diagnostics

---

## Phase 5: Documentation And Examples — ❌ Not started

**Current state:** a parser-focused `README.md` exists at the repo root but
covers the full parser module, not `seam` in isolation. No Rowan-model
mapping, no standalone examples.

### Task 5.1: Publish-grade README — ❌ Not done

README sections:
- quick start
- API overview
- minimal end-to-end example using parse events
- red-node traversal example
- rowan mapping and non-goals

Acceptance criteria:
- README examples are checked and run by test workflow
- no stale references to parser-internal packages

### Task 5.2: API reference generation workflow — ⚠️ Partial

Steps:
- run `moon info` ✅ (already part of standard workflow)
- review/commit `pkg.generated.mbti` ✅ (already committed and up to date)

**Remaining work:**
- No undocumented public symbol check is automated; must be done manually
  after Task 1.1 reduces the surface area.

Acceptance criteria:
- generated API file matches intended surface
- no undocumented public symbol remains

---

## Phase 6: CI — ❌ Not started

### Task 6.1: CI gates — ❌ Not done

Required CI commands:
- `moon check --target all`
- `moon test`
- `moon info`

**Current state:** no CI exists for the standalone `seam` module
(CI would be set up after Phase 3 standalone bootstrap).

Acceptance criteria:
- all three gates run on every push to the default branch
- failures are visible before any release attempt

---

## Execution Order

0. Phase 0 (naming) — rename green/red/term to CST/SyntaxNode/AST before any API work
1. Phase 1 (API hardening) — resolve `pub(all)` field visibility, add invariant docs
2. Phase 2 (contract decisions + API freeze) — record `node_at`/`width` decision
3. Phase 3 (standalone module bootstrap) — extract to independent module/repo
4. Phase 4 (tests) — panic tests + property tests in standalone module
5. Phase 5 (docs/examples) — publish-grade README
6. Phase 6 (CI) — gates on standalone module

## Risks

- API leaks from permissive field visibility (`pub(all)` structs) can force
  unnecessary follow-up releases. **High risk — must fix before Phase 3.**
- Deferred API decisions (`node_at`, `width`) can create documentation/code drift.
- Hash/equality semantics are easy to regress without dedicated tests.
- `token_count` (incremental-parser detail) exposed on `GreenNode` — may be
  wrong to include in a language-agnostic standalone module.

## Success Metric

External user can add `dowdiness/seam`, build a small CST via events, traverse
with `SyntaxNode`, and pass `moon check`/`moon test` with no knowledge of this
parser repository.
