# Incremental Parser TODO (Compact)

**Last Updated:** 2026-02-25
**Status:** Phases 1-7 complete; Phase 8 (Grammar Expansion) is next

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

### Phase 5 (Generic Parser Framework) — Complete ✅

**Goal:** Extract a reusable `ParserContext[T, K]` API so any MoonBit project can define a parser against the green tree / error recovery / incremental infrastructure.

- ✅ `src/core/` package with `TokenInfo[T]`, `Diagnostic[T]`, `LanguageSpec[T, K]`, `ParserContext[T, K]`
- ✅ `ParserContext::new` (array-based) and `ParserContext::new_indexed` (closure-based, zero-copy)
- ✅ Full method surface: `peek`, `at`, `at_eof`, `emit_token`, `start_node`, `finish_node`, `mark`, `start_at`, `error`, `bump_error`, `emit_zero_width`, `emit_error_placeholder`, `flush_trivia`
- ✅ `parse_with` top-level entry point
- ✅ `Diagnostic[T]` generic with `got_token : T` (captures offending token at parse time)
- ✅ `LanguageSpec` includes `token_is_trivia` and `print_token`
- ✅ Lambda parser migrated to `ParserContext` as reference implementation (`lambda_spec.mbt`, `green_parser.mbt`)
- ✅ `run_parse` private helper eliminates duplicated parse-and-build sequence
- ✅ Trivia-inclusive lexer integration: whitespace in token stream, `flush_trivia()` before grammar return
- ✅ 367 total tests passing; 56 benchmarks passing
- ✅ Design: `docs/plans/2026-02-23-generic-parser-design.md`
- ✅ Implementation plan: `docs/plans/2026-02-23-generic-parser-impl.md`
- ✅ Benchmark snapshot: `docs/benchmark_history.md` (2026-02-24 entry)

### Phase 6 (Generic Incremental Reuse) — Complete ✅

**Goal:** Wire `ReuseCursor[T, K]` from `src/core/` into `ParserContext` via `node()` / `wrap_at()` combinators so incremental subtree reuse fires transparently for any grammar.

- ✅ `ReuseCursor[T, K]` generic struct in `src/core/` with `collect_old_tokens`, `try_reuse`, `seek_node_at`, `advance_past`
- ✅ `ParserContext` gains `reuse_cursor`, `reuse_count`, `set_reuse_cursor`, `set_reuse_diagnostics` fields/methods
- ✅ `node(kind, body)` combinator: skips `body` closure on reuse hit (O(edit) skip)
- ✅ `wrap_at(mark, kind, body)` combinator: retroactive wrapping; inner `node()` calls still reuse
- ✅ Lambda grammar migrated: `parse_atom` uses `ctx.node()`, `parse_binary_op`/`parse_application` use `ctx.wrap_at()`
- ✅ `run_parse_incremental` helper wires cursor + diagnostics; replaces duplicated entry-point logic
- ✅ Old lambda-specific `ReuseCursor` removed from `src/parser/` (3 files, 946 lines deleted)
- ✅ `make_reuse_cursor` factory updated to return `@core.ReuseCursor[Token, SyntaxKind]`
- ✅ Reuse verified by `reuse_count > 0` tests (not just structural equality)
- ✅ `prev_diagnostics?` parameter added to cursor entry points for diagnostic replay on reused subtrees
- ✅ Phase 3 cursor benchmarks added; cursor overhead documented for 110-token flat grammar
- ✅ 372 total tests passing; 59 benchmarks passing
- ✅ Design: `docs/plans/2026-02-24-generic-incremental-reuse-design.md`

### Phase 7 (ParserDb) — Complete ✅

**Goal:** Build `ParserDb`, a `Signal`/`Memo`-backed Salsa-style incremental pipeline using `CstNode` value equality for automatic stage backdating.

**Architecture:** `source_text : Signal[String]` → `tokens : Memo[TokenStage]` → `cst : Memo[CstStage]`

- ✅ `dowdiness/incr` added as git submodule dependency (`incr/`)
- ✅ `TokenStage` enum (`Ok(Array[TokenInfo])` / `Err(String)`) with `Eq` for backdating
- ✅ `CstStage` struct (`cst: CstNode`, `diagnostics: Array[String]`) with `Eq`
- ✅ `ParserDb::new()` wires `Signal` + two `Memo` nodes in a single `Runtime`
- ✅ `ParserDb::set_source()` / `cst()` / `diagnostics()` / `term()` public API
- ✅ `term()` uses Option B error routing: tokenization failure → `AstNode::error(...)`
- ✅ `diagnostics()` returns `.copy()` to prevent mutation of memoized backing array
- ✅ `parse_cst_to_ast_node` test comparison uses direct call (no `catch` swallowing errors)
- ✅ Interfaces updated via `moon info && moon fmt`
- ✅ 343 total tests passing; 59 benchmarks passing
- ✅ Implementation plan: `docs/plans/2026-02-25-incr-parser-db.md`

## Optional / On-Demand

### Priority 4: Future Enhancements
- [ ] Position-based fragment finding (only if profiling shows need)
- [ ] Consider tree-sitter migration (only if requirements change)
- [ ] Semantics-aware reuse checks (follow-set/context-sensitive) for projectional/live editing
- [x] Generic `ReuseCursor[T]` — move cursor into `src/core/` so `parse_with_cursor` is fully generic (Phase 2)
