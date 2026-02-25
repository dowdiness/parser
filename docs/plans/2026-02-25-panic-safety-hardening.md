# Panic-Safety Hardening Plan

**Goal:** Ensure internal runtime invariants are restored even when user-provided closures abort during `Runtime::batch` or `Memo` recomputation paths.

**Architecture:** Introduce explicit guard-style cleanup for mutable runtime state (`batch_depth`, tracking stack frames, and `in_progress` flags) around user callbacks. Add regression tests for invariant restoration and follow-up operation safety.

**Tech Stack:** MoonBit. Validate with `moon check`, `moon test`, and `moon coverage analyze`.

---

### Scope

In scope:
- Panic/abort cleanup behavior in:
  - `Runtime::batch`
  - `Memo::force_recompute`
  - verification path interactions (`maybe_changed_after*`) when recompute fails
- New regression tests that assert runtime remains usable after failure paths
- Minor internal refactors needed to centralize cleanup logic

Out of scope:
- Changing public API semantics of `get()` vs `get_result()`
- Push-pull invalidation work
- GC / cell deletion

---

### Task 1: Characterize current failure behavior with targeted tests

**Files:**
- Modify: `internal/batch_wbtest.mbt`
- Modify: `internal/verify_wbtest.mbt`
- (Optional) Add: `internal/panic_safety_wbtest.mbt`

**Step 1: Add tests that exercise aborting callbacks and recompute closures**

Add tests for:
- `Runtime::batch` where closure aborts after `batch_depth` increment
- memo compute closure abort after `in_progress = true` and tracking push
- follow-up operation on same runtime to confirm whether state was restored

**Step 2: Run focused tests**

Run:
```bash
moon test -p dowdiness/incr/internal -f batch_wbtest.mbt
moon test -p dowdiness/incr/internal -f verify_wbtest.mbt
```

Expected: at least one test demonstrates invariant leakage (current behavior).

---

### Task 2: Add cleanup guards around `Runtime::batch`

**Files:**
- Modify: `internal/runtime.mbt`

**Step 1: Refactor `Runtime::batch` to guarantee depth restoration**

Ensure:
- `batch_depth` decrement happens on all exits
- outermost commit is only attempted when state is balanced
- underflow guard remains as defense-in-depth

Implementation detail:
- If MoonBit supports a `defer`/finally-like construct, use it directly.
- If not, extract closure execution into a helper that returns a `Result`/status and apply explicit cleanup before rethrow/abort.

**Step 2: Keep current semantics**

Do not change:
- nested batch behavior
- commit ordering
- callback order (per-cell before global)

---

### Task 3: Add cleanup guards around memo recomputation

**Files:**
- Modify: `internal/memo.mbt`
- Modify (if needed): `internal/runtime.mbt`

**Step 1: Harden `Memo::force_recompute`**

Guarantee cleanup on all exits:
- `cell.in_progress = false`
- balanced `push_tracking` / `pop_tracking` (or stack cleanup equivalent)

**Step 2: Preserve behavior**

Keep:
- cycle detection semantics
- dep diff + subscriber maintenance logic
- backdating semantics

---

### Task 4: Verify interaction with iterative verifier

**Files:**
- Modify (if needed): `internal/verify.mbt`
- Modify tests in: `internal/verify_wbtest.mbt`, `internal/cycle_test.mbt`

**Step 1: Ensure verifier cleanup remains correct on error paths**

Validate:
- `cleanup_stack` still clears all frame `in_progress` flags
- no stale flags remain after recompute errors

**Step 2: Add targeted assertions**

Add tests that:
- trigger `Err(CycleError)` during verification
- subsequently perform successful reads/writes using same runtime

---

### Task 5: Full validation and coverage check

Run:
```bash
moon check
moon test
moon coverage analyze
```

Acceptance criteria:
- all tests pass
- new panic-safety tests pass
- uncovered lines in critical cleanup branches are reduced

---

### Task 6: Documentation follow-up

**Files:**
- Modify: `docs/todo.md`
- Modify (if needed): `docs/design.md`

Update:
- mark panic-safety hardening task status
- document invariant restoration guarantees in internals section

