# Incremental Parser TODO (Compact)

**Last Updated:** 2026-02-01
**Status:** ✅ Core cleanup done; Phase 1 implemented; benchmarks pending

## Current Focus

### Phase 1 (Incremental Lexer) — Implemented ✅
**Pending:** benchmarks on 100+ token inputs
- [ ] Add Phase 1 incremental lexer benchmark case and record results in `BENCHMARKS.md`
- Command: `moon benchmark performance_benchmark.mbt`

## Optional / On-Demand

### Priority 4: Future Enhancements
- [ ] Position-based fragment finding (only if profiling shows need)
- [ ] Consider tree-sitter migration (only if requirements change)
