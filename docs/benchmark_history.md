# Benchmark History

Historical snapshots from project benchmark runs (full suite and focused runs).

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
