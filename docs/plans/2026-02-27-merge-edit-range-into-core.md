# Merge `edit` + `range` into `core` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Merge the `edit` and `range` packages into `core` to eliminate future cycle-dependency risk between the parser infrastructure and its primitive value types.

**Architecture:** `Edit` and `Range` move as new files into `src/core/`. Their test files move with them. All consumers that previously imported `dowdiness/parser/edit` or `downdiness/parser/range` switch to `downdiness/parser/core` (alias `@core`), and all `@edit.`/`@range.` call-site qualifiers become `@core.`. After verifying tests pass, the now-empty `src/edit/` and `src/range/` directories are deleted.

**Tech Stack:** MoonBit, `moon` build tool (`moon check`, `moon test`, `moon info`, `moon fmt`)

---

### Task 1: Add `Edit` to `core`

**Files:**
- Create: `src/core/edit.mbt`
- Create: `src/core/edit_test.mbt`
- Modify: `src/core/moon.pkg`

**Step 1: Copy `edit.mbt` into `core/`**

Create `src/core/edit.mbt` with the exact contents of `src/edit/edit.mbt` (no changes needed — the file has no package-qualified references).

**Step 2: Copy `edit_test.mbt` into `core/`**

Create `src/core/edit_test.mbt` with the exact contents of `src/edit/edit_test.mbt` (no changes needed — tests use unqualified `Edit::new(...)` which works in blackbox test context).

**Step 3: Verify `core/moon.pkg` — no change needed yet**

`Edit` has no external imports, so `core/moon.pkg` does not need updating for this step.

**Step 4: Run check (expect failure on duplicate symbol — that's OK for now)**

```bash
cd /path/to/parser && moon check 2>&1 | head -30
```

`edit` package still exists so there will be no error yet. We're just making sure the new files parse.

**Step 5: Commit**

```bash
git add src/core/edit.mbt src/core/edit_test.mbt
git commit -m "feat(core): add Edit type to core package"
```

---

### Task 2: Add `Range` to `core` and update `moon.pkg`

**Files:**
- Create: `src/core/range.mbt`
- Create: `src/core/range_test.mbt`
- Modify: `src/core/moon.pkg`

**Step 1: Copy `range.mbt` into `core/`**

Create `src/core/range.mbt` with the exact contents of `src/range/range.mbt` (no changes needed).

**Step 2: Copy `range_test.mbt` into `core/`**

Create `src/core/range_test.mbt` with the exact contents of `src/range/range_test.mbt` (no changes needed).

**Step 3: Add `cmp` import to `core/moon.pkg`**

`Range::minimum_by_length` calls `@cmp.minimum_by_key`. Add this import:

```
import {
  "dowdiness/seam" @seam,
  "moonbitlang/core/cmp",
}
```

**Step 4: Check `core` package compiles**

```bash
moon check 2>&1 | grep -i error | head -20
```

Expected: no errors about `core` package.

**Step 5: Commit**

```bash
git add src/core/range.mbt src/core/range_test.mbt src/core/moon.pkg
git commit -m "feat(core): add Range type to core package"
```

---

### Task 3: Update `lexer` to use `@core`

**Files:**
- Modify: `src/lexer/moon.pkg`
- Modify: `src/lexer/token_buffer.mbt`

**Step 1: Update `src/lexer/moon.pkg`**

Replace:
```
import {
  "dowdiness/parser/token",
  "dowdiness/parser/edit",
}
```
With:
```
import {
  "dowdiness/parser/token",
  "dowdiness/parser/core" @core,
}
```

**Step 2: Update `src/lexer/token_buffer.mbt`**

Replace all occurrences of `@edit.Edit` with `@core.Edit`:

```bash
sed -i 's/@edit\.Edit/@core.Edit/g' src/lexer/token_buffer.mbt
```

Affected lines (for verification):
- `TokenBuffer::update` signature: `edit : @edit.Edit` → `edit : @core.Edit`
- `map_start_pos` signature: `edit : @edit.Edit` → `edit : @core.Edit`
- `map_end_pos` signature: `edit : @edit.Edit` → `edit : @core.Edit`

**Step 3: Verify lexer compiles**

```bash
moon check 2>&1 | grep "lexer" | head -10
```

Expected: no lexer errors.

**Step 4: Commit**

```bash
git add src/lexer/moon.pkg src/lexer/token_buffer.mbt
git commit -m "refactor(lexer): use @core.Edit instead of @edit.Edit"
```

---

### Task 4: Update `crdt` to use `@core`

**Files:**
- Modify: `src/crdt/moon.pkg`
- Modify: `src/crdt/crdt_integration.mbt`
- Modify: `src/crdt/crdt_integration_test.mbt`

**Step 1: Update `src/crdt/moon.pkg`**

Replace:
```
import {
  "dowdiness/parser/ast",
  "dowdiness/parser/edit",
  "dowdiness/parser/incremental",
  "moonbitlang/core/hashmap",
}
```
With:
```
import {
  "dowdiness/parser/ast",
  "dowdiness/parser/core" @core,
  "dowdiness/parser/incremental",
  "moonbitlang/core/hashmap",
}
```

**Step 2: Update `src/crdt/crdt_integration.mbt`**

```bash
sed -i 's/@edit\.Edit/@core.Edit/g' src/crdt/crdt_integration.mbt
```

Affected line: `ParsedDocument::edit` parameter `edit : @edit.Edit` → `edit : @core.Edit`

**Step 3: Update `src/crdt/crdt_integration_test.mbt`**

```bash
sed -i 's/@edit\.Edit/@core.Edit/g' src/crdt/crdt_integration_test.mbt
```

Affected lines: all `@edit.Edit::insert(...)`, `@edit.Edit::replace(...)` calls in tests.

**Step 4: Verify crdt compiles**

```bash
moon check 2>&1 | grep "crdt" | head -10
```

Expected: no crdt errors.

**Step 5: Commit**

```bash
git add src/crdt/moon.pkg src/crdt/crdt_integration.mbt src/crdt/crdt_integration_test.mbt
git commit -m "refactor(crdt): use @core.Edit instead of @edit.Edit"
```

---

### Task 5: Update `incremental` to use `@core`

**Files:**
- Modify: `src/incremental/moon.pkg`
- Modify: `src/incremental/damage.mbt`
- Modify: `src/incremental/incremental_parser.mbt`
- Modify: `src/incremental/damage_test.mbt`
- Modify: `src/incremental/incremental_parser_test.mbt`
- Modify: `src/incremental/incremental_differential_fuzz_test.mbt`
- Modify: `src/incremental/phase4_correctness_test.mbt`
- Modify: `src/incremental/interner_integration_test.mbt`

**Step 1: Update `src/incremental/moon.pkg`**

Remove the `edit` and `range` import lines (keep `@core` — it's already there):

```
import {
  "dowdiness/parser/token",
  "dowdiness/parser/ast",
  "dowdiness/parser/lexer",
  "dowdiness/parser/core" @core,
  "dowdiness/parser/parser" @parse,
  "dowdiness/seam" @seam,
}

import {
} for "test"
```

**Step 2: Bulk-replace in all incremental source and test files**

```bash
sed -i 's/@edit\.Edit/@core.Edit/g' \
  src/incremental/damage.mbt \
  src/incremental/incremental_parser.mbt \
  src/incremental/damage_test.mbt \
  src/incremental/incremental_parser_test.mbt \
  src/incremental/incremental_differential_fuzz_test.mbt \
  src/incremental/phase4_correctness_test.mbt \
  src/incremental/interner_integration_test.mbt

sed -i 's/@range\.Range/@core.Range/g' \
  src/incremental/damage.mbt \
  src/incremental/incremental_parser.mbt \
  src/incremental/damage_test.mbt
```

**Step 3: Verify incremental compiles**

```bash
moon check 2>&1 | grep "incremental" | head -10
```

Expected: no incremental errors.

**Step 4: Run incremental tests**

```bash
moon test --package dowdiness/parser/incremental 2>&1 | tail -5
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add src/incremental/moon.pkg \
  src/incremental/damage.mbt \
  src/incremental/incremental_parser.mbt \
  src/incremental/damage_test.mbt \
  src/incremental/incremental_parser_test.mbt \
  src/incremental/incremental_differential_fuzz_test.mbt \
  src/incremental/phase4_correctness_test.mbt \
  src/incremental/interner_integration_test.mbt
git commit -m "refactor(incremental): use @core.Edit and @core.Range instead of separate packages"
```

---

### Task 6: Update `benchmarks` to use `@core`

**Files:**
- Modify: `src/benchmarks/moon.pkg`
- Modify: `src/benchmarks/benchmark.mbt`

**Step 1: Update `src/benchmarks/moon.pkg`**

Replace `"dowdiness/parser/edit"` with `"dowdiness/parser/core" @core`.

Current file:
```
import {
  "dowdiness/parser/edit",
  "dowdiness/parser/lexer",
  "dowdiness/parser" @parse,
  "dowdiness/parser/incremental",
  "dowdiness/parser/lambda" @lambda,
  "dowdiness/parser/crdt",
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
}
```

Note: `benchmarks` already imports `@parse`, `@lambda`, `@incremental` — all of which now depend on `@core`. However, `benchmarks` must still declare the `@core` import explicitly (MoonBit requires explicit imports).

After:
```
import {
  "dowdiness/parser/core" @core,
  "dowdiness/parser/lexer",
  "dowdiness/parser/parser" @parse,
  "dowdiness/parser/incremental",
  "dowdiness/parser/lambda" @lambda,
  "dowdiness/parser/crdt",
  "dowdiness/seam" @seam,
  "moonbitlang/core/bench",
}
```

**Step 2: Update `src/benchmarks/benchmark.mbt`**

```bash
sed -i 's/@edit\.Edit/@core.Edit/g' src/benchmarks/benchmark.mbt
```

**Step 3: Verify benchmarks compile**

```bash
moon check 2>&1 | grep "benchmarks" | head -10
```

Expected: no benchmarks errors.

**Step 4: Commit**

```bash
git add src/benchmarks/moon.pkg src/benchmarks/benchmark.mbt
git commit -m "refactor(benchmarks): use @core.Edit instead of @edit.Edit"
```

---

### Task 7: Full check and delete old packages

**Step 1: Run full check**

```bash
moon check 2>&1 | head -30
```

Expected: zero errors.

**Step 2: Run all tests**

```bash
moon test 2>&1 | tail -10
```

Expected: all tests pass.

**Step 3: Delete `src/edit/` and `src/range/`**

```bash
rm -rf src/edit src/range
```

**Step 4: Run check again to confirm nothing depends on deleted packages**

```bash
moon check 2>&1 | head -30
```

Expected: zero errors. If any package still references the deleted packages it will be caught here.

**Step 5: Run all tests again**

```bash
moon test 2>&1 | tail -10
```

Expected: all tests pass. Note that `core` now has 4 test files (`lib_wbtest.mbt`, `edit_test.mbt`, `range_test.mbt`, and any existing tests).

**Step 6: Commit deletion**

```bash
git add -A
git commit -m "refactor: delete edit and range packages (merged into core)"
```

---

### Task 8: Finalize — update interfaces and format

**Step 1: Regenerate `.mbti` interface files**

```bash
moon info
```

Expected: `src/core/pkg.generated.mbti` now includes `Edit` and `Range` types and their methods. `src/edit/pkg.generated.mbti` and `src/range/pkg.generated.mbti` no longer exist.

**Step 2: Verify the interface diff looks right**

```bash
git diff src/core/pkg.generated.mbti
```

Expected: `Edit` struct + methods and `Range` struct + methods appended to the existing core interface.

**Step 3: Check `crdt/pkg.generated.mbti` updated**

```bash
git diff src/crdt/pkg.generated.mbti
```

Expected: `ParsedDocument::edit` parameter type changes from `@edit.Edit` to `@core.Edit`.

**Step 4: Format all files**

```bash
moon fmt
```

**Step 5: Final full test run**

```bash
moon test 2>&1 | tail -10
```

Expected: all tests pass.

**Step 6: Commit**

```bash
git add -A
git commit -m "chore: regenerate interfaces and format after edit+range→core merge"
```
