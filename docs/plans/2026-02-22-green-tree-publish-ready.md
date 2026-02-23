# Green-Tree Publish-Readiness Plan (Standalone Module)

**Date:** 2026-02-22  
**Status:** Draft

## Goal

Publish `green-tree` as an independent MoonBit module with a stable, documented,
tested API suitable for first public release (`v0.1.0`).

## Scope

In scope:
- Standalone module packaging and metadata
- API hardening for `green-tree` core types
- Test coverage and documentation for external users
- CI and release checklist

Out of scope:
- Migration from current internal import paths
- Backward-compatibility shims
- Breaking-change mitigation for existing consumers

## Release Target

Module name: `dowdiness/green-tree`  
Initial version: `0.1.0`

## Definition Of Done

- Module can be added by dependency and built in a clean project.
- Public API is intentional and documented.
- `moon check --target all`, `moon test`, and `moon info` pass in CI.
- README examples are executable (`mbt check`) and pass tests.
- `v0.1.0` tag + publish steps are executed and verified.

## Open Concerns (Track Before Release Freeze)

1. API contract granularity:
   - Freeze must be method/field-level, not just top-level symbol names, so
     `pkg.generated.mbti` diffs are meaningful review gates.
2. Deferred API decisions:
   - Resolve include/defer for `RedNode::node_at(position : Int)` and
     `GreenNode::width()` before release freeze.
3. Scope coordination:
   - These publish concerns are not blockers for starting `incr` integration
     implementation in this repository.

---

## Phase 1: API Hardening

### Task 1.1: Visibility and invariants audit

Audit items:
- mutable/public fields that should be private or method-based
- error messages for invalid state transitions (`EventBuffer`, `build_tree`)
- stable semantics for equality/hash behavior

Acceptance criteria:
- each public type/method has concise docs for invariants
- trait impl behavior (`Eq`, `Hash`) is documented and tested

### Task 1.2: Rowan-model documentation

Document mapping:
- `RawKind` ~ rowan raw kind
- green tree vs red tree responsibilities
- event stream to tree construction model

Acceptance criteria:
- section included in README
- examples illustrate the model directly

---

## Phase 2: Contract And API Freeze

### Task 2.1: Freeze public API surface

Target public symbols:
- `RawKind`
- `GreenToken`
- `GreenElement`
- `GreenNode`
- `RedNode`
- `ParseEvent`
- `EventBuffer`
- `build_tree`
- hash utilities (`combine_hash`, `string_hash`)

Deliverables:
- API contract section in this plan (or separate `docs/api-contract.md`)
- explicit notes for any deferred API

Acceptance criteria:
- `pkg.generated.mbti` matches contract exactly
- no accidental exports remain

### Task 2.2: Decide deferred vs included APIs

Decide now:
- Include or defer `RedNode::node_at(position : Int)`
- Include or defer `GreenNode::width()` alias for `text_len`

Acceptance criteria:
- decision recorded in docs
- implementation and tests match the decision

---

## Phase 3: Standalone Module Bootstrap

### Task 3.1: Create module skeleton

Files:
- `moon.mod.json`
- `moon.pkg` (root package manifest)
- `README.mbt.md` (symlink `README.md` if desired)
- `LICENSE`
- source files under package root

Required metadata in `moon.mod.json`:
- `name: "dowdiness/green-tree"`
- `version: "0.1.0"`
- `repository`
- `license`
- `keywords`
- `description`

Acceptance criteria:
- module builds without project-local dependencies
- package imports are minimal and intentional

### Task 3.2: Move/copy core implementation

Source set:
- `green_node.mbt`
- `red_node.mbt`
- `event.mbt`
- `hash.mbt`

Acceptance criteria:
- behavior matches current internal `green-tree`
- no parser/language-specific code in standalone module

---

## Phase 4: Test Completion

### Task 4.1: Unit + panic tests

Required coverage:
- constructor correctness (`text_len`, hash derivation)
- equality/hash fast-path behavior
- event balancing invariants
- red-node offsets and traversal
- deferred/included API behavior (`node_at`, `width`) per Phase 2

Acceptance criteria:
- all tests pass with `moon test`
- panic/abort paths are explicitly tested

### Task 4.2: Property-style confidence checks

Suggested properties:
- deterministic structural hash for identical trees
- `build_tree` preserves concatenated text length
- red node child offsets are monotonic and contiguous

Acceptance criteria:
- property tests added where practical
- failures produce actionable diagnostics

---

## Phase 5: Documentation And Examples

### Task 5.1: Publish-grade README

README sections:
- quick start
- API overview
- minimal end-to-end example using parse events
- red-node traversal example
- rowan mapping and non-goals

Acceptance criteria:
- README examples are checked and run by test workflow
- no stale references to parser-internal packages

### Task 5.2: API reference generation workflow

Steps:
- run `moon info`
- review/commit `pkg.generated.mbti`

Acceptance criteria:
- generated API file matches intended surface
- no undocumented public symbol remains

---

## Phase 6: CI And Release

### Task 6.1: CI gates

Required CI commands:
- `moon check --target all`
- `moon test`
- `moon info`

Acceptance criteria:
- all gates enforced on default branch
- failures block release

### Task 6.2: Release checklist

Release steps:
1. verify clean CI
2. verify `version` and changelog/release notes
3. tag `v0.1.0`
4. publish to mooncakes
5. run clean-room install/build smoke test

Smoke test:
- new temp project depends on `dowdiness/green-tree@0.1.0`
- builds and executes README example

Acceptance criteria:
- published artifact is installable and usable without local code

---

## Execution Order

1. Phase 1 (API hardening)  
2. Phase 2 (contract decisions + API freeze)  
3. Phase 3 (standalone module bootstrap)  
4. Phase 4 (tests)  
5. Phase 5 (docs/examples)  
6. Phase 6 (CI + publish)

## Risks

- API leaks from permissive field visibility can force unnecessary follow-up releases.
- Deferred API decisions (`node_at`, `width`) can create documentation/code drift.
- Hash/equality semantics are easy to regress without dedicated tests.

## Success Metric

External user can add `dowdiness/green-tree`, build a small syntax tree via
events, traverse with `RedNode`, and pass `moon check`/`moon test` with no
knowledge of this parser repository.
