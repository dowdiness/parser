# Incremental Parser TODO (Compact)

**Last Updated:** 2026-02-01
**Status:** Phase 1 implemented; Phase 2 scaffolding done, integration pending

## Current Focus

### Phase 1 (Incremental Lexer) — Implemented ✅
**Pending:** benchmarks on 100+ token inputs
- [ ] Add Phase 1 incremental lexer benchmark case and record results in `BENCHMARKS.md`
- Command: `moon benchmark performance_benchmark.mbt`

### Phase 2 (Green Tree) — Scaffolding Complete, Integration Pending
**Done (scaffolding):**
- ✅ `SyntaxKind` enum unifying tokens and node types (`green_tree.mbt`)
- ✅ `GreenToken`, `GreenNode`, `GreenElement` core types (`green_tree.mbt`)
- ✅ `TreeBuilder` with stack-based construction (`tree_builder.mbt`)
- ✅ `GreenParser` / `parse_green()` with whitespace emission (`green_parser.mbt`)
- ✅ `RedNode` with offset-based position computation (`red_tree.mbt`)
- ✅ `green_to_term_node` / `green_to_term` backward-compat conversion (`green_convert.mbt`)
- ✅ `ParenExpr` distinguishes `x` from `(x)` from `((x))`
- ✅ Mixed binary operator handling in conversion (`1 + 2 - 3`)
- ✅ Trailing whitespace emission at EOF
- ✅ 30+ green tree tests (structure, positions, backward compatibility)
- ✅ 195 total tests passing

**Next (integration):**
- [ ] Wire `parse_green` into primary `parse()` / `parse_tree()` path (replace direct `TermNode` construction)
- [ ] Use `RedNode` for position queries in production code (not just tests)
- [ ] Ensure public API compatibility and update docs
- [ ] Verify no performance regression on existing benchmarks

**Known issues (non-blocking):**
- `EofToken` and `ErrorNode` in `SyntaxKind` are unused — intentional placeholders for Phase 3
- `TreeBuilder::start_node` ignores its `kind` param (kind is passed to `finish_node` instead)
- Structural sharing is value-equal, not pointer-equal — pointer sharing comes with Phase 4 reuse cursor

## Optional / On-Demand

### Priority 4: Future Enhancements
- [ ] Position-based fragment finding (only if profiling shows need)
- [ ] Consider tree-sitter migration (only if requirements change)
