# `seam` Publish-Readiness Plan (Standalone Module)

**Date:** 2026-02-22
**Updated:** 2026-02-25
**Status:** In Progress — Phases 0–2 complete; Phases 3–5 not started; Phase 6 (CI) deferred

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
- CI gates (deferred — not needed yet)

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
- CI gates are deferred — not required for publish-readiness at this stage.

## Open Concerns (Track Before Release Freeze)

1. API contract granularity:
   - Freeze must be method/field-level, not just top-level symbol names, so
     `pkg.generated.mbti` diffs are meaningful review gates.
2. Deferred API decisions:
   - Resolve include/defer for `SyntaxNode::node_at(position : Int)` and
     `CstNode::width()` before release freeze.
   - **Current status:** neither method exists; decision unrecorded. Must be
     recorded in Task 2.2 before Phase 3.
3. Exposed implementation fields:
   - `CstNode`, `CstToken`, `CstElement`, `RawKind` are declared
     `pub(all)` — every field is accessible externally. Field
     `CstNode.children` mutability is the main concern (see Task 1.1).
     Fields `hash` and `token_count` are decided kept (see Task 3.2).
   - `EventBuffer.events : Array[ParseEvent]` is a public field; callers
     can bypass `push`/`mark`/`start_at` and corrupt the event stream.
     **Decision: make private** (see Task 1.1).
   - Must be resolved in Task 1.1 before API freeze.
4. Scope coordination:
   - These publish concerns are not blockers for starting `incr` integration
     implementation in this repository.
   - Once Phase 3 (standalone module) is complete, the `crdt` monorepo can
     reference `seam` via a path dependency — no mooncakes publish needed.
     Path dep syntax: `"dowdiness/seam": { "path": "../seam" }` in
     `moon.mod.json`.

---

## Phase 0: Naming Alignment — ✅ Complete

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

### Task 0.1: Rename `green-tree` package and types — ✅ Done

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

### Task 0.2: Rename `red-tree` types — ✅ Done

Scope:
- Rename `RedNode` → `SyntaxNode` within the CST package (or a new `syntax`
  package if a clean separation is preferred)
- Update all callers

Acceptance criteria:
- `moon check` and `moon test` pass with 0 regressions

### Task 0.3: Rename `term-tree` to `ast` — ✅ Done

**Scope note:** `TermNode` lives in `src/parser/` (the lambda grammar layer),
not in `src/green-tree/`. This rename is a `dowdiness/parser` concern and does
not block any `seam` phase. Do it for naming consistency across the codebase,
but it is independent of `seam` publish-readiness.

Scope:
- Rename relevant source files in `src/parser/`
- Rename `TermNode` → `AstNode` and related types
- Update all callers

Acceptance criteria:
- `moon check` and `moon test` pass with 0 regressions

---

## Phase 1: API Hardening — ⚠️ Partial

### Task 1.1: Visibility and invariants audit — ✅ Done

Audit items:
- mutable/public fields that should be private or method-based
- error messages for invalid state transitions (`EventBuffer`, `build_tree`)
- stable semantics for equality/hash behavior

**Current state (pre-Phase-0 names):**
- `CstNode`, `CstToken`, `CstElement`, `RawKind` are all `pub(all)` —
  implementation fields (`hash`, `token_count`, `children`) are exposed.
- `EventBuffer.events` is a plain public field; the raw array is accessible
  without going through `push`/`mark`/`start_at`.
- `CstToken::Eq` and `CstToken::Hash` use the cached `hash` field; this
  behavior is implemented but not documented as a stability guarantee.
- `RawKind::inner` is `#deprecated` — good, no action needed.

**Decisions recorded:**
- `CstNode.token_count` — **keep**. Computed for free during `CstNode::new`
  children traversal; removing forces O(subtree) recount at every use site.
- `EventBuffer.events` — **make private**. Only `push`/`mark`/`start_at`
  should be accessible; raw array access allows callers to corrupt event
  stream invariants.
- `CstNode.hash`, `CstToken.hash` — **keep as `pub` fields** (read-only
  cached value; useful for external consumers implementing custom caches).
  Document as stable.
- `CstNode.children` — **decision pending Task 1.1 audit**: either keep
  `pub(all)` with documented invariants, or expose via a method.

**Remaining work:**
- Make `EventBuffer.events` private; expose read-only access via method if needed.
- Audit `CstNode.children` — document invariants or restrict to method access.
- Add invariant docs to each public type: what `hash` represents,
  what `token_count` counts, what `EventBuffer` balancing requires.
- Document `Eq`/`Hash` fast-path semantics as a stability guarantee.

Acceptance criteria:
- each public type/method has concise docs for invariants
- trait impl behavior (`Eq`, `Hash`) is documented and tested

### Task 1.2: Rowan-model documentation — ✅ Done

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

## Phase 2: Contract And API Freeze — ✅ Complete

### Task 2.1: Freeze public API surface — ✅ Done

Target public symbols (post-Phase-0 names; currently exist under old names):
- `RawKind` ✅
- `CstToken` ✅ (currently `GreenToken`)
- `CstElement` ✅ (currently `GreenElement`)
- `CstNode` ✅ (currently `GreenNode`)
- `SyntaxNode` ✅ (currently `RedNode`)
- `ParseEvent` ✅
- `EventBuffer` ✅
- `build_tree` ✅
- `build_tree_interned` ✅
- `Interner` ✅
- `combine_hash`, `string_hash` ✅

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

### Task 2.2: Decide deferred vs included APIs — ✅ Done

Decide now:
- Include or defer `SyntaxNode::node_at(position : Int)`
- Include or defer `CstNode::width()` alias for `text_len`

**Decision recorded:**
- `SyntaxNode::node_at` — **deferred**. No current callers; position-on-boundary and trivia semantics need explicit design before freeze.
- `CstNode::width()` — **deferred**. Redundant alias; `text_len` is already a public field on `pub(all) CstNode`.

Acceptance criteria:
- decision recorded in docs
- implementation and tests match the decision

---

## Phase 3: Standalone Module Bootstrap — ❌ Not started

**Decision:** `seam` will be extracted as a **git submodule** (new repository
`dowdiness/seam`), added to `dowdiness/parser` via `git submodule add`.
`dowdiness/parser`'s `moon.mod.json` will reference it as a path dependency:
`"dowdiness/seam": { "path": "seam" }`.

**Current state:** `seam` (currently `green-tree`) lives at `src/green-tree/`
inside the `dowdiness/parser` module (`moon.mod.json` name = `"dowdiness/parser"`).
It cannot be added as a standalone dependency today.

### Task 3.1: Create module skeleton — ❌ Not done

New repository: `https://github.com/dowdiness/seam`

Files:
- `moon.mod.json`
- `moon.pkg` (root package manifest)
- `README.md`
- `LICENSE`
- source files under package root

Required metadata in `moon.mod.json`:
- `name: "dowdiness/seam"`
- `version: "0.1.0"`
- `repository`
- `license`
- `keywords`
- `description`
- `deps: { "moonbitlang/quickcheck": "<version>" }` (needed for Task 4.2 property tests)

Acceptance criteria:
- module builds without project-local dependencies
- package imports are minimal and intentional

### Task 3.2: Move/copy core implementation — ❌ Not done

Source set (all present in current `src/green-tree/`, will move to `seam/`):
- `green_node.mbt` ✅ — includes `CstNode`, `CstToken`, `CstElement`, `RawKind`
- `red_node.mbt` ✅ — includes `SyntaxNode`
- `event.mbt` ✅ — includes `EventBuffer`, `ParseEvent`, `build_tree`
- `hash.mbt` ✅ — includes `combine_hash`, `string_hash`
- `interner.mbt` ✅ — includes `Interner`, `build_tree_interned`

**Explicit inclusions decided:**
- `Interner` + `build_tree_interned` — structural sharing/deduplication is core
  to the module's value; useful beyond incremental parsing
- `CstNode.token_count` — computed for free during `CstNode::new` children
  traversal; removing forces O(subtree) recount at every use site; keep
- `has_errors(error_node_kind, error_token_kind)` — language-agnostic via
  `RawKind` parameters; include

Acceptance criteria:
- behavior matches current internal `green-tree` / `seam`
- no parser/language-specific code in standalone module

### Task 3.3: Wire `dowdiness/parser` to standalone `seam` — ❌ Not done

After extraction:
- Add `seam` as a git submodule to `dowdiness/parser`
- Add `"dowdiness/seam": { "path": "seam" }` to `dowdiness/parser`'s
  `moon.mod.json` deps
- Remove `src/green-tree/` from `dowdiness/parser` source tree
- Verify `moon check` and `moon test` pass with 0 regressions

Acceptance criteria:
- `dowdiness/parser` builds against standalone `seam` via path dep
- no source duplication between the two modules

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

**Current state:** `moonbitlang/quickcheck` is a dependency of `dowdiness/parser`
but not of standalone `seam`. Task 3.1 must add it to `seam`'s `moon.mod.json`
before property tests can be written.

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

## Phase 6: CI — ⏸️ Deferred

Not needed yet. When CI is added, required commands are:
- `moon check --target all`
- `moon test`
- `moon info`

---

## Execution Order

0. Phase 0 (naming) — rename green/red/term to CST/SyntaxNode/AST before any API work
1. Phase 1 (API hardening) — resolve `pub(all)` field visibility, add invariant docs
2. Phase 2 (contract decisions + API freeze) — record `node_at`/`width` decision
3. Phase 3 (standalone module bootstrap) — extract to independent module/repo
4. Phase 4 (tests) — panic tests + property tests in standalone module
5. Phase 5 (docs/examples) — publish-grade README
6. Phase 6 (CI) — deferred

## Document Organization After Separation

After Phase 3 (git submodule extraction), docs split as follows:

**`dowdiness/seam` repo — minimal, user-facing:**
```
seam/
  README.md        ← Phase 5 publish-grade doc (event model, API overview, examples)
  CHANGELOG.md     ← version history starting at 0.1.0
  moon.mod.json
  *.mbt / *_wbtest.mbt
```
No `docs/plans/` in `seam`. External users do not need implementation history.

**`dowdiness/parser` repo — keeps everything else:**
```
parser/
  README.md                                      ← update to reference seam as dep
  TODO.md
  seam/                                          ← git submodule
  docs/
    plans/
      2026-02-22-green-tree-publish-ready.md     ← stays (decision log for extraction)
      2026-02-23-generic-parser-design.md        ← stays
      2026-02-24-generic-incremental-reuse-design.md ← stays
    benchmark_history.md                         ← stays (parser perf, seam is a dep)
```

| Doc | Location | Reason |
|---|---|---|
| This plan (`2026-02-22`) | `parser/docs/plans/` | Decision log for extraction; stays as archive |
| Parser plans (`2026-02-23/24`) | `parser/docs/plans/` | Parser-layer concerns |
| `benchmark_history.md` | `parser/docs/` | Measures parser performance; seam is a dep |
| `TODO.md` | `parser/` | Parser work tracking |
| `seam/README.md` | `seam/` | Written fresh in Phase 5; lives in seam repo |
| `seam/CHANGELOG.md` | `seam/` | Belongs to seam's release history |

---

## Risks

- API leaks from permissive field visibility (`pub(all)` structs) can force
  unnecessary follow-up releases. **High risk — must fix before Phase 3.**
- Deferred API decisions (`node_at`, `width`) can create documentation/code drift.
- Hash/equality semantics are easy to regress without dedicated tests.
- `CstNode.children` visibility — if kept `pub(all)`, callers can build
  structurally invalid trees by mutating the array. Document immutability
  contract clearly or restrict to method access.

## Success Metric

External user can add `dowdiness/seam`, build a small CST via events, traverse
with `SyntaxNode`, and pass `moon check`/`moon test` with no knowledge of this
parser repository.
