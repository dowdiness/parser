# Parser Benchmarks

Performance benchmarks for the incremental parser implementation.

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

## Benchmark Results

### Phase 1: Incremental Lexer (110 tokens)

*Measured 2026-02-02, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| full tokenize (110 tokens) | 1.18 us | 1.16 us ... 1.22 us |
| incremental: edit at start | 2.15 us | 2.07 us ... 2.34 us |
| incremental: edit in middle | 2.01 us | 1.96 us ... 2.06 us |
| incremental: edit at end | 1.92 us | 1.87 us ... 1.96 us |
| full re-tokenize after edit | 1.23 us | 1.17 us ... 1.47 us |

**Methodology:** Each incremental benchmark includes `TokenBuffer::new()` (which
calls `tokenize()` internally at ~1.18 us). Subtracting this setup cost gives
the isolated update time:

| Edit location | Update cost (estimated) | vs full re-tokenize | Speedup |
|---------------|------------------------|---------------------|---------|
| Start | ~0.97 us | 1.23 us | ~1.3x |
| Middle | ~0.83 us | 1.23 us | ~1.5x |
| End | ~0.74 us | 1.23 us | ~1.7x |

**Observations:**
- Incremental update is faster than full re-tokenize at all edit positions
- Edits near the end are cheapest: fewer tokens need position adjustment after the splice
- All operations are well under the 16ms real-time editing target (< 3 us total)
- At 110 tokens the speedup is modest (1.3-1.7x) because full tokenize is already fast;
  larger inputs will show greater benefit as update cost stays proportional to damaged
  region while full tokenize grows linearly

### Parse Scaling

*Measured 2026-02-02, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| parse scaling - small (5 tokens) | 0.79 us | 0.76 us ... 0.87 us |
| parse scaling - medium (15 tokens) | 3.53 us | 3.41 us ... 3.70 us |
| parse scaling - large (30+ tokens) | 6.31 us | 5.91 us ... 7.16 us |

### Basic Operations

*Measured 2026-02-02, `moon bench --package parser --release`*

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| full parse - simple (`42`) | 0.37 us | 0.36 us ... 0.39 us |
| full parse - lambda (`lx.x`) | 0.70 us | 0.69 us ... 0.72 us |
| full parse - nested lambdas | 1.88 us | 1.86 us ... 1.91 us |
| full parse - arithmetic | 1.48 us | 1.44 us ... 1.60 us |
| full parse - complex | 3.49 us | 3.45 us ... 3.53 us |
| tokenization (`lf.lx.f x`) | 0.25 us | 0.25 us ... 0.26 us |

### Incremental Parser

| Benchmark | Mean | Range (min ... max) |
|-----------|------|---------------------|
| incremental - initial parse | 0.14 us | 0.13 us ... 0.14 us |
| incremental - small edit | 0.43 us | 0.42 us ... 0.45 us |
| incremental - multiple edits | 0.83 us | 0.82 us ... 0.85 us |
| incremental - replacement | 0.66 us | 0.66 us ... 0.67 us |

## Expected Performance Characteristics

### Time Complexity

| Operation | Complexity | Notes |
|-----------|------------|-------|
| Initial parse | O(n) | n = source length |
| Incremental edit | O(d) | d = damaged region |
| Damage tracking | O(m) | m = tree nodes |

### Benchmark Targets

Based on Wagner-Graham algorithm and Tree-sitter benchmarks:

| Metric | Target | Current Status |
|--------|--------|----------------|
| Full parse (small) | < 1ms | 0.37-0.79 us |
| Full parse (medium) | < 5ms | 3.49-3.53 us |
| Full tokenize (110 tokens) | < 1ms | 1.18 us |
| Incremental tokenize (110 tokens) | < full tokenize | 0.74-0.97 us (1.3-1.7x faster) |
| Incremental edit | < 1ms | 0.43-0.83 us |
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

✅ **Incremental edits faster than full reparse**
✅ **Linear scaling with input size**
✅ **< 16ms for typical edits**

### Performance Red Flags

⚠️ **Incremental slower than full reparse** → Damage tracking issue
⚠️ **Exponential scaling** → Algorithm complexity problem
⚠️ **High memory usage** → AST node allocation issue

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
   moon bench parser --release
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
  run: moon bench parser --release

- name: Compare against baseline
  run: |
    moon bench parser --baseline previous_results.json
```

## References

- MoonBit Benchmarks: https://docs.moonbitlang.com/en/latest/language/benchmarks.html
- Wagner-Graham Paper: https://dl.acm.org/doi/10.1145/293677.293678
- Tree-sitter Benchmarks: https://tree-sitter.github.io/tree-sitter/
