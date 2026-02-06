# Incremental Parser TODO (Compact)

**Last Updated:** 2026-02-03
**Status:** Phases 1-4 complete; Phase 5 (Grammar Expansion) is next

## Completed

### Phase 1 (Incremental Lexer) — Complete ✅
- [x] Add Phase 1 incremental lexer benchmark case and record results in `BENCHMARKS.md`
  - 110-token input (`1 + 2 + 3 + ... + 55`), edits at start/middle/end
  - Incremental update: ~0.74-0.97 us vs full re-tokenize: ~1.23 us (1.3-1.7x speedup)
  - All operations well under 16ms real-time target

### Phase 2 (Green Tree) — Complete ✅
**Done (scaffolding + event buffer refactor):**
- ✅ `SyntaxKind` enum unifying tokens and node types (`green_tree.mbt`)
- ✅ `GreenToken`, `GreenNode`, `GreenElement` core types (`green_tree.mbt`)
- ✅ `ParseEvent` enum + `EventBuffer` struct + `build_tree` function (`parse_events.mbt`)
- ✅ Replaced old stack-based `TreeBuilder` with flat event buffer architecture
- ✅ `GreenParser` uses `EventBuffer` with `mark()`/`start_at()` for retroactive wrapping (`green_parser.mbt`)
- ✅ `RedNode` with offset-based position computation (`red_tree.mbt`)
- ✅ `green_to_term_node` / `green_to_term` backward-compat conversion (`green_convert.mbt`)
- ✅ `ParenExpr` distinguishes `x` from `(x)` from `((x))`
- ✅ Mixed binary operator handling in conversion (`1 + 2 - 3`)
- ✅ Trailing whitespace emission at EOF
- ✅ 30+ green tree tests (structure, positions, backward compatibility)
- ✅ 247 total tests passing

### Baseline/Docs Sync (Step 1) — Complete ✅
- [x] Sync roadmap/todo status text with current state and latest validation counts
- [x] Refresh benchmark numbers in `BENCHMARKS.md` from latest local run
- [x] Rename misleading "cache effectiveness" benchmark labels in `performance_benchmark.mbt`
- [x] Add benchmark history log at `docs/benchmark_history.md`

### Correctness Oracle Hardening (Step 2) — Complete ✅
- [x] Add deterministic differential random-edit tests (`incremental_differential_fuzz_test.mbt`)
- [x] Add malformed-input termination stress with recovery-to-valid regression checks
- [x] Add fast/long filterable test split (`*differential-fast*`, `*differential-long*`)
- [x] Document test split commands in `README.md`

**Integration (complete):**
- [x] Wire `parse_green` into primary `parse()` / `parse_tree()` path (replace direct `TermNode` construction)
- [x] Use `RedNode` for position queries in production code (`convert_red` replaces manual offset tracking)
- [x] Ensure public API compatibility and update docs (`red_to_term_node` added, README updated)
- [x] Verify no performance regression on existing benchmarks

### Phase 3 (Error Recovery) — Complete ✅
- [x] Synchronization points via `at_stop_token()` (RightParen, Then, Else, EOF)
- [x] `ErrorNode` and `ErrorToken` used for partial tree construction
- [x] `bump_error()` consumes unexpected tokens wrapped in ErrorNode
- [x] `expect()` emits zero-width ErrorToken for missing tokens
- [x] Error budget (`max_errors = 50`) prevents infinite loops
- [x] `parse_green_recover()` returns (tree, diagnostics) without raising
- [x] Comprehensive fuzz tests (`error_recovery_phase3_test.mbt`)

### Phase 4 (Subtree Reuse) — Complete ✅
- [x] `ReuseCursor` struct with 4-condition reuse protocol (`reuse_cursor.mbt`)
- [x] Integration in `parse_atom()` for all 5 atom kinds
- [x] Trailing context check prevents false reuse from structural changes
- [x] Strict damage boundary handling (adjacent nodes not reused)
- [x] `IncrementalParser` creates cursor and tracks reuse count
- [x] Benchmarks: 3-6x speedup for localized edits
- [x] Comprehensive correctness tests (`phase4_correctness_test.mbt`)
- [x] 287 total tests passing

**Known issues (non-blocking):**
- `EofToken` in `SyntaxKind` is unused — placeholder for future use
- 80% reuse rate requires Phase 5 let bindings (lambda trees are left-leaning)

## Optional / On-Demand

### Priority 4: Future Enhancements
- [ ] Position-based fragment finding (only if profiling shows need)
- [ ] Consider tree-sitter migration (only if requirements change)
- [ ] Semantics-aware reuse checks (follow-set/context-sensitive) for projectional/live editing
