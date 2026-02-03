# Benchmark History

Historical snapshots from `moon bench --package parser --release`.

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
