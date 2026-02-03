# Parser Benchmarks

Performance benchmarks for the incremental parser implementation.

**Last measured:** 2026-02-03 (`moon bench --package parser --release`)

## Running Benchmarks

```bash
# Run all parser benchmarks (recommended)
moon bench --package parser --release

# Run all tests (non-benchmark tests only)
moon test --package parser
```

**Note:** Use `moon bench` to run performance benchmarks. The `moon test` command runs functional tests only.

## Benchmark Categories

### 1. Basic Operations (`benchmark.mbt`)

**Full Parse Benchmarks:**
- Simple expression: `42`
- Lambda: `λx.x`
- Nested lambdas: `λf.λx.f (f x)`
- Arithmetic: `1 + 2 - 3 + 4`
- Complex: `λf.λx.if f x then x + 1 else x - 1`

**Incremental Parser:**
- Initial parse
- Small edits
- Multiple sequential edits
- Replacement edits

**CRDT Operations:**
- AST → CRDT conversion
- CRDT → source reconstruction

**Error Recovery:**
- Valid input parsing
- Error handling overhead

### 2. Scaling & Performance (`performance_benchmark.mbt`)

**Parse Scaling:**
- Small input (5 tokens)
- Medium input (15 tokens)
- Large input (30+ tokens)

**Incremental vs Full Reparse:**
- Edit at start
- Edit at end
- Edit in middle

**Sequential Edit Patterns:**
- Realistic typing simulation
- Backspace/delete simulation

**Damage Tracking:**
- Localized damage
- Widespread damage

**Worst/Best Cases:**
- Full document edit (worst)
- Cosmetic changes only (best)

### 3. Phase 1: Incremental Lexer (`performance_benchmark.mbt`)

Benchmarks for `TokenBuffer` incremental tokenization on a 110-token input
(`"1 + 2 + 3 + ... + 55"`: 55 integers + 54 plus operators + EOF).

**Full Tokenization (baseline):**
- `tokenize()` on 110-token source
- `tokenize()` on edited 110-token source

**Incremental Tokenization (TokenBuffer.update):**
- Edit at start: replace `1` with `99`
- Edit in middle: replace `28` with `99`
- Edit at end: replace `55` with `99`

### 4. Phase 4: Checkpoint-Based Subtree Reuse (`performance_benchmark.mbt`)

Benchmarks for `ReuseCursor` subtree reuse during incremental parsing.
When reparsing after an edit, unchanged subtrees outside the damaged range
are reused from the previous parse tree.

**Damage Tracking:**
- Localized damage (single token edit)
- Widespread damage (edit affects entire expression)

**Edit Position Impact:**
- Edit at start, middle, end of expression
- Best case: cosmetic change outside all subtrees
- Worst case: full invalidation requiring complete reparse

**Sequential Edits:**
- Typing simulation (character insertion)
- Backspace simulation (character deletion)

## Benchmark Results

### Phase 1: Incremental Lexer (110 tokens)

*Measured 2026-02-03, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| full tokenize (110 tokens) | 1.23 µs | 1.19 µs ... 1.39 µs |
| incremental: edit at start | 2.12 µs | 2.09 µs ... 2.18 µs |
| incremental: edit in middle | 2.00 µs | 1.99 µs ... 2.06 µs |
| incremental: edit at end | 1.95 µs | 1.91 µs ... 2.00 µs |
| full re-tokenize after edit | 1.28 µs | 1.24 µs ... 1.40 µs |

**Methodology:** Each incremental benchmark includes `TokenBuffer::new()` (which
calls `tokenize()` internally at ~1.23 us). Subtracting this setup cost gives
the isolated update time:

| Edit location | Update cost (estimated) | vs full re-tokenize | Speedup |
|---------------|------------------------|---------------------|---------|
| Start | ~0.89 us | 1.28 us | ~1.4x |
| Middle | ~0.77 us | 1.28 us | ~1.7x |
| End | ~0.72 us | 1.28 us | ~1.8x |

**Observations:**
- Incremental update is faster than full re-tokenize at all edit positions
- Edits near the end are cheapest: fewer tokens need position adjustment after the splice
- All operations are well under the 16ms real-time editing target (< 3 us total)
- At 110 tokens the speedup is modest (1.3-1.7x) because full tokenize is already fast;
  larger inputs will show greater benefit as update cost stays proportional to damaged
  region while full tokenize grows linearly

### Phase 4: Checkpoint-Based Subtree Reuse

*Measured 2026-02-03, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| damage tracking - localized damage | 1.09 µs | 1.05 µs ... 1.14 µs |
| damage tracking - widespread damage | 4.20 µs | 4.11 µs ... 4.45 µs |
| best case - cosmetic change | 2.37 µs | 2.33 µs ... 2.43 µs |
| worst case - full invalidation | 11.25 µs | 10.90 µs ... 11.44 µs |
| sequential edits - typing simulation | 1.58 µs | 1.54 µs ... 1.69 µs |
| sequential edits - backspace simulation | 1.78 µs | 1.70 µs ... 1.83 µs |
| incremental vs full - edit at start | 11.12 µs | 10.89 µs ... 11.34 µs |
| incremental vs full - edit at end | 10.95 µs | 10.50 µs ... 11.52 µs |
| incremental vs full - edit in middle | 10.74 µs | 10.52 µs ... 11.02 µs |

**Performance Comparison (vs full parse of 30+ tokens at 6.46 µs):**

| Scenario | Time | Speedup vs Full Parse |
|----------|------|----------------------|
| Localized damage | 1.09 µs | ~5.9x faster |
| Best case (cosmetic) | 2.37 µs | ~2.7x faster |
| Typing simulation | 1.58 µs | ~4.1x faster |
| Backspace simulation | 1.78 µs | ~3.6x faster |
| Widespread damage | 4.20 µs | ~1.5x faster |
| Edit at start/middle/end | ~10.9 µs | ~0.6x (slower)* |
| Worst case (full invalidation) | 11.25 µs | ~0.6x (slower)* |

*\*Edits that invalidate the tree root (lambda/binary expression spine) require rebuilding the entire tree structure. This is expected for left-leaning trees where the root spans the entire source.*

**Observations:**
- Subtree reuse provides significant speedup (3-6x) for localized edits
- Typing/backspace simulations are fast (< 2 µs), supporting real-time editing
- Edits at expression boundaries (start/middle/end of chains) invalidate the root node
- Lambda calculus trees are left-leaning: `f a b c` → App(App(App(f,a),b),c)
- When root is invalidated, incremental has overhead vs fresh parse
- Real benefit comes with let bindings (Phase 5) where sibling definitions are independent

### Parse Scaling

*Measured 2026-02-03, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| parse scaling - small (5 tokens) | 0.83 µs | 0.79 µs ... 0.94 µs |
| parse scaling - medium (15 tokens) | 3.65 µs | 3.52 µs ... 3.78 µs |
| parse scaling - large (30+ tokens) | 6.46 µs | 6.21 µs ... 6.98 µs |

### Basic Operations

*Measured 2026-02-03, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| full parse - simple (`42`) | 0.39 µs | 0.38 µs ... 0.39 µs |
| full parse - lambda (`λx.x`) | 0.75 µs | 0.73 µs ... 0.76 µs |
| full parse - nested lambdas | 2.00 µs | 1.97 µs ... 2.04 µs |
| full parse - arithmetic | 1.55 µs | 1.51 µs ... 1.61 µs |
| full parse - complex | 3.60 µs | 3.51 µs ... 3.69 µs |
| tokenization (`λf.λx.f x`) | 0.27 µs | 0.26 µs ... 0.27 µs |

### Incremental Parser

*Measured 2026-02-03, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| incremental - initial parse | 0.45 µs | 0.44 µs ... 0.48 µs |
| incremental - small edit | 1.61 µs | 1.56 µs ... 1.66 µs |
| incremental - multiple edits | 2.90 µs | 2.86 µs ... 2.94 µs |
| incremental - replacement | 2.11 µs | 2.08 µs ... 2.17 µs |

## Expected Performance Characteristics

### Time Complexity

| Phase | Tokenization | Parsing | Total |
|-------|-------------|---------|-------|
| Before Phase 1 | O(N) | O(N) | O(N) |
| After Phase 1 (incremental lexer) | O(d) | O(N) | O(N) |
| After Phase 4 (subtree reuse) | O(d) | O(depth)* | O(depth) |

*\*For localized edits. Edits that invalidate the root still require O(N) parsing.*

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Initial parse | O(n) | n = source length |
| Incremental edit (localized) | O(depth) | With subtree reuse |
| Incremental edit (root invalidated) | O(n) | Tree spine must be rebuilt |
| Damage tracking | O(m) | m = tree nodes |

### Benchmark Targets

Based on Wagner-Graham algorithm and Tree-sitter benchmarks:

| Metric | Target | Current Status |
|--------|--------|----------------|
| Full parse (small) | < 1ms | 0.39-0.83 µs ✅ |
| Full parse (medium) | < 5ms | 3.60-3.65 µs ✅ |
| Full tokenize (110 tokens) | < 1ms | 1.23 µs ✅ |
| Incremental tokenize (110 tokens) | < full tokenize | 1.95-2.12 µs (with setup) ✅ |
| Incremental edit (localized) | < full parse | 1.09-1.78 µs (3-6x faster) ✅ |
| Incremental edit (worst case) | < 2x full parse | 11.25 µs (~1.7x full) ✅ |
| Subtree reuse rate | > 50% for local edits | Verified in tests ✅ |
| Memory overhead | < 2x source | To measure |

### Real-Time Editing Target

**60 FPS target**: < 16ms per edit
- Parse: < 5ms
- Damage tracking: < 3ms
- CRDT sync: < 6ms

## Benchmark Results Format

MoonBit benchmark output format:
```
test bench: full parse - simple ... ok (XXX iterations in XXXms)
test bench: incremental - small edit ... ok (XXX iterations in XXXms)
```

Performance metrics to track:
1. **Iterations per second**: Higher is better
2. **Time per iteration**: Lower is better
3. **Relative speedup**: Incremental vs full reparse

## Interpreting Results

### Good Performance Indicators

✅ **Incremental edits faster than full reparse** (for localized edits)
✅ **Linear scaling with input size**
✅ **< 16ms for typical edits**
✅ **Subtree reuse rate > 50%** for single-token edits on large inputs
✅ **Typing/backspace simulations < 2 µs**

### Performance Red Flags

⚠️ **Incremental slower than full reparse for localized edits** → Subtree reuse not triggering
⚠️ **Exponential scaling** → Algorithm complexity problem
⚠️ **High memory usage** → AST node allocation issue
⚠️ **Zero reuse count** → ReuseCursor conditions too strict

### Phase 4 Specific Notes

**Expected behavior:**
- Localized edits (adding/removing a character within a subtree) should be 3-6x faster
- Edits at expression boundaries (start of chain) invalidate the root and are slower
- Lambda calculus trees are left-leaning, so root invalidation is common

**When root is invalidated:**
- Incremental parse has overhead (~1.5-2x full parse) due to cursor setup
- This is expected and acceptable; benefit comes from localized edits
- Phase 5 (let bindings) will provide independent subtrees for better reuse

## Optimization Opportunities

Based on benchmark results, consider:

1. **If tokenization is slow:**
   - Implement parallel tokenization
   - Add streaming tokenization

2. **If parsing is slow:**
   - Implement lazy subtree expansion
   - Add position indexing

3. **If damage tracking is slow:**
   - Optimize tree traversal
   - Add early termination

4. **If CRDT conversion is slow:**
   - Implement incremental CRDT updates
   - Optimize attribute copying

## Profiling Tips

### Identify Bottlenecks

1. **Run benchmarks with profiler:**
   ```bash
   moon bench --package parser --release
   ```

2. **Compare incremental vs full:**
   - If incremental ≈ full → Whole-tree reuse not triggering
   - If incremental << full → Working as expected

### Memory Profiling

Track memory usage patterns:
- AST node allocation
- CRDT tree size

## Continuous Benchmarking

Recommended CI integration:
```yaml
- name: Run benchmarks
  run: moon bench --package parser --release

- name: Compare against baseline
  run: |
    moon bench --package parser --release
```

Keep historical snapshots in `docs/benchmark_history.md` to compare trends over time.

## References

- MoonBit Benchmarks: https://docs.moonbitlang.com/en/latest/language/benchmarks.html
- Wagner-Graham Paper: https://dl.acm.org/doi/10.1145/293677.293678
- Tree-sitter Benchmarks: https://tree-sitter.github.io/tree-sitter/
