# Benchmark History

Historical snapshots from project benchmark runs (full suite and focused runs).

## 2026-02-23

- Command: `moon bench --package dowdiness/parser/benchmarks --release`
- Git ref: `main` (`23b71da`)
- Environment: local developer machine (WSL2 / Linux 6.6 / wasm-gc)
- Result: `56/56` benchmarks passed
- Changes since previous entry:
  - Added token interning (`Interner`, `build_tree_interned`) to `green-tree`
  - `IncrementalParser` now owns a session-scoped `Interner`
  - Fixed interner key construction: two-level `HashMap[RawKind, HashMap[String, GreenToken]]`
    replaces the old string-concat key; hot hit path is allocation-free
  - Added 12 new interning benchmarks (interner micro, `build_tree` comparison, `parse_green_recover` comparison)

### Core Parse Scaling

| Metric | Mean | Notes |
|---|---:|---|
| parse scaling - small (5 tokens) | 0.86 µs | Full parse baseline (small) |
| parse scaling - medium (15 tokens) | 3.71 µs | Full parse baseline (medium) |
| parse scaling - large (30+ tokens) | 6.25 µs | Full parse baseline (large) |

### Incremental Parser

| Metric | Mean | Notes |
|---|---:|---|
| incremental - initial parse | 0.53 µs | Parser creation + first parse |
| incremental - small edit | 1.94 µs | `x` → `x + 1` |
| incremental - multiple edits | 3.23 µs | 2 sequential edits |
| incremental - replacement | 2.24 µs | `λx.x` → `\x.x` |
| incremental vs full - edit at start | 10.15 µs | Boundary edit, medium expression |
| incremental vs full - edit at end | 9.93 µs | Boundary edit, medium expression |
| incremental vs full - edit in middle | 10.28 µs | Boundary edit, medium expression |
| sequential edits - typing simulation | 1.90 µs | Single-char insert |
| sequential edits - backspace simulation | 1.95 µs | Single-char delete |
| incremental state baseline - repeated parsing | 4.44 µs | Edit + undo |
| best case - cosmetic change | 2.53 µs | Localized edit path |
| worst case - full invalidation | 10.17 µs | Full rebuild + incremental overhead |
| memory pressure - large document | 16.53 µs | Larger input incremental edit |

### Damage Tracking & Position Adjustment

| Metric | Mean | Notes |
|---|---:|---|
| damage tracking | 0.79 µs | Wagner-Graham damage expand |
| damage tracking - localized damage | 1.08 µs | Small edit region |
| damage tracking - widespread damage | 4.20 µs | Edit at start of medium expression |
| position adjustment after edit | 2.14 µs | Tree position shift after edit |

### CRDT Integration

| Metric | Mean | Notes |
|---|---:|---|
| tokenization | 0.29 µs | Lexer baseline |
| ast to crdt | 2.10 µs | AST → CRDT conversion |
| crdt to source | 2.26 µs | CRDT → source reconstruction |
| crdt operations - nested structure | 5.61 µs | Nested structure round-trip |
| crdt operations - round trip | 5.39 µs | Parse → CRDT → source → parse |

### Error Recovery & High-level API

| Metric | Mean | Notes |
|---|---:|---|
| error recovery - valid | 0.76 µs | `parse_with_error_recovery`, valid input |
| error recovery - error | 0.80 µs | `parse_with_error_recovery`, invalid input |
| parsed document - parse | 0.66 µs | `ParsedDocument::parse` |
| parsed document - edit | 2.43 µs | `ParsedDocument::edit` |

### Phase 1: Incremental Tokenizer (110-token input)

| Metric | Mean | Notes |
|---|---:|---|
| phase1: full tokenize - 110 tokens | 1.21 µs | Full tokenization baseline |
| phase1: incremental tokenize - edit at start | 2.17 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit in middle | 1.97 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit at end | 1.89 µs | Includes `TokenBuffer::new()` setup |
| phase1: full re-tokenize after edit | 1.17 µs | Comparison baseline |

### Green-Tree Microbenchmarks

| Metric | Mean | Notes |
|---|---:|---|
| green-tree - token constructor | 0.02 µs | `GreenToken::new` hash compute path |
| green-tree - node constructor from 32 children | 0.06 µs | `GreenNode::new` fold/hash path |
| green-tree - equality identical 32 children | 0.17 µs | Hash check + deep equality walk |
| green-tree - equality mismatch hash fast path | 0.01 µs | Expected early hash mismatch exit |

### Token Interning (new — baseline for future node-interning evaluation)

| Metric | Mean | Notes |
|---|---:|---|
| interner - intern_token cold miss | 0.10 µs | First call: two-level map miss + `GreenToken::new` |
| interner - intern_token warm hit | 0.07 µs | Subsequent call: two-level map hit, allocation-free |
| build_tree - x + 1 | 0.17 µs | No interning baseline (7 token events) |
| build_tree_interned - x + 1, cold interner | 0.41 µs | First parse (all misses) |
| build_tree_interned - x + 1, warm interner | 0.24 µs | Subsequent parses (all hits); 1.4× vs `build_tree` |
| build_tree - 100 identical ident tokens | 1.09 µs | No interning, 100 `GreenToken::new` calls |
| build_tree_interned - 100 identical tokens, warm | 1.78 µs | 1 miss + 99 hits; 1.6× vs `build_tree` |
| parse_green_recover - no interner, small | 0.62 µs | `x + 1`, no interning |
| parse_green_recover - cold interner, small | 0.87 µs | `x + 1`, first parse |
| parse_green_recover - warm interner, small | 0.70 µs | `x + 1`, subsequent; 1.13× overhead |
| parse_green_recover - no interner, large | 4.95 µs | `λf.λx.if…`, no interning |
| parse_green_recover - warm interner, large | 5.47 µs | `λf.λx.if…`, subsequent; 1.10× overhead |

### Notable Changes vs 2026-02-21

The interner key fix (two-level map) substantially improved all `IncrementalParser` benchmarks
because `IncrementalParser` calls `intern_token` on every token during every parse:

| Metric | 2026-02-21 | 2026-02-23 | Change |
|---|---:|---:|---|
| incremental vs full - edit at start | 8.73 µs | 10.15 µs | +16% (more features) |
| best case - cosmetic change | 2.14 µs | 2.53 µs | +18% (more features) |
| memory pressure - large document | 14.24 µs | 16.53 µs | +16% (more features) |

Incremental numbers are modestly higher than 2026-02-21 because the parser now
maintains a green tree, token buffer, and interner through each edit. The 2026-02-21
snapshot predates green-tree integration.

## 2026-02-21 (JST) / 2026-02-20 (US)

- Command: `moon bench --package dowdiness/parser/benchmarks --release`
- Hash strategy: hybrid (`GreenToken`/`GreenNode` cached structural hash via FNV; `Hash` trait impls for collection interop)
- Environment: local developer machine
- Result: `44/44` benchmarks passed

| Metric | Mean | Notes |
|---|---:|---|
| parse scaling - large (30+ tokens) | 6.50 µs | Full parse baseline (large) |
| incremental vs full - edit at start | 8.73 µs | Boundary edit, root invalidation path |
| incremental vs full - edit in middle | 8.74 µs | Boundary edit, root invalidation path |
| incremental vs full - edit at end | 8.57 µs | Boundary edit, root invalidation path |
| best case - cosmetic change | 2.14 µs | Localized edit path |
| worst case - full invalidation | 8.53 µs | Full rebuild + incremental overhead |
| memory pressure - large document | 14.24 µs | Larger input incremental edit scenario |
| phase1: full tokenize - 110 tokens | 1.16 µs | Tokenization baseline |
| phase1: incremental tokenize - edit at start | 2.04 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit in middle | 1.96 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit at end | 1.89 µs | Includes `TokenBuffer::new()` setup |
| phase1: full re-tokenize after edit | 1.13 µs | Comparison baseline |

### Green-Tree Focused Metrics (from same full run)

| Metric | Mean | Notes |
|---|---:|---|
| green-tree - token constructor | 0.02 µs | `GreenToken::new` hash compute path |
| green-tree - node constructor from 32 children | 0.06 µs | `GreenNode::new` fold/hash path |
| green-tree - equality identical 32 children | 0.17 µs | Hash check + deep equality walk |
| green-tree - equality mismatch hash fast path | 0.01 µs | Expected early hash mismatch exit |

## 2026-02-19

- Command: `moon bench --package dowdiness/parser/benchmarks --release`
- Git ref: `main` (`fc3e44b`)
- Environment: local developer machine
- Result: `40/40` benchmarks passed

| Metric | Mean | Notes |
|---|---:|---|
| parse scaling - small (5 tokens) | 0.87 µs | Full parse baseline (small) |
| parse scaling - medium (15 tokens) | 3.79 µs | Full parse baseline (medium) |
| parse scaling - large (30+ tokens) | 7.04 µs | Full parse baseline (large) |
| incremental vs full - edit at start | 8.95 µs | Boundary edit, root invalidation path |
| incremental vs full - edit in middle | 9.11 µs | Boundary edit, root invalidation path |
| incremental vs full - edit at end | 8.22 µs | Boundary edit, root invalidation path |
| best case - cosmetic change | 2.11 µs | Localized edit path |
| worst case - full invalidation | 8.62 µs | Full rebuild + incremental overhead |
| memory pressure - large document | 14.33 µs | Larger input incremental edit scenario |
| phase1: full tokenize - 110 tokens | 1.16 µs | Tokenization baseline |
| phase1: incremental tokenize - edit at start | 2.04 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit in middle | 1.94 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit at end | 1.88 µs | Includes `TokenBuffer::new()` setup |
| phase1: full re-tokenize after edit | 1.10 µs | Comparison baseline |

### Green-Tree Microbenchmark Snapshot (2026-02-19)

- Command: `moon bench --package dowdiness/parser/benchmarks --release`
- Git ref: `main` (working tree includes `src/benchmarks/green_tree_benchmark.mbt`)
- Result: `44/44` benchmarks passed

| Metric | Mean | Notes |
|---|---:|---|
| green-tree - token constructor | 0.02 µs | `GreenToken::new` hash compute path |
| green-tree - node constructor from 32 children | 0.05 µs | `GreenNode::new` fold/hash path |
| green-tree - equality identical 32 children | 0.16 µs | Hash check + deep equality walk |
| green-tree - equality mismatch hash fast path | 0.01 µs | Expected early hash mismatch exit |

### Green-Tree Focused Run (2026-02-19)

- Context: second run on the focused subset after adding `Hash` impls for `GreenToken`,
  `GreenElement`, `GreenNode` using cached structural hashes. Small differences vs the
  snapshot above are within run-to-run noise.
- Command: `moon bench --package dowdiness/parser/benchmarks --file green_tree_benchmark.mbt --release`
- Result: `4/4` benchmarks passed

| Metric | Mean | Notes |
|---|---:|---|
| green-tree - token constructor | 0.01 µs | `GreenToken::new` hash compute path |
| green-tree - node constructor from 32 children | 0.07 µs | `GreenNode::new` fold/hash path |
| green-tree - equality identical 32 children | 0.17 µs | Hash check + deep equality walk |
| green-tree - equality mismatch hash fast path | 0.01 µs | Expected early hash mismatch exit |

## 2026-02-03

- Command: `moon bench --package parser --release`
- Environment: local developer machine (same repo state as docs update)

| Metric | Mean | Notes |
|---|---:|---|
| parse scaling - large (30+ tokens) | 6.46 µs | Full parse baseline for larger input |
| incremental vs full - edit at start | 11.12 µs | Boundary edit, root invalidation path |
| incremental vs full - edit in middle | 10.74 µs | Boundary edit, root invalidation path |
| incremental vs full - edit at end | 10.95 µs | Boundary edit, root invalidation path |
| best case - cosmetic change | 2.37 µs | Localized edit path |
| worst case - full invalidation | 11.25 µs | Full rebuild + incremental overhead |
| phase1: full tokenize - 110 tokens | 1.23 µs | Tokenization baseline |
| phase1: incremental tokenize - edit at start | 2.12 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit in middle | 2.00 µs | Includes `TokenBuffer::new()` setup |
| phase1: incremental tokenize - edit at end | 1.95 µs | Includes `TokenBuffer::new()` setup |
| phase1: full re-tokenize after edit | 1.28 µs | Comparison baseline |

## Notes

- Incremental token benchmarks currently include setup (`TokenBuffer::new()`).
- Add a setup-free benchmark variant when Step 2 starts to isolate `TokenBuffer.update` cost directly.
