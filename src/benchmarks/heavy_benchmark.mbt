// Heavy benchmarks: realistic IDE session simulation.
// Measures parse latency at scale, per-edit latency over long sessions,
// interner growth, and structural sharing effectiveness.
//
// Run with: moon bench --package dowdiness/parser/benchmarks --release

// ─── Source generators ───────────────────────────────────────────────────────

///|
/// Deterministic PRNG (same as differential fuzz tests).
fn heavy_next_seed(seed : Int) -> Int {
  (seed * 1103515245 + 12345) % 2147483647
}

///|
/// Build a large lambda expression with ~200 tokens.
/// Structure: nested if-then-else with lambda bindings and arithmetic.
///
/// Example output shape:
///   λa.λb.if a + b then (λc.if c then c + 1 else c - 1) else (λd.d + 2)
fn make_large_source() -> String {
  let mut s = ""
  // 8 nested lambdas: λa.λb.λc.λd.λe.λf.λg.λh.
  let vars = ["a", "b", "c", "d", "e", "f", "g", "h"]
  for v in vars {
    s = s + "λ" + v + "."
  }
  // Body: chain of if-then-else with arithmetic
  s = s + make_if_chain(vars, 0)
  s
}

///|
fn make_if_chain(vars : Array[String], depth : Int) -> String {
  if depth >= 4 {
    // Base: arithmetic expression using available vars
    let i = depth % vars.length()
    let j = (depth + 1) % vars.length()
    return vars[i] + " + " + vars[j] + " - 1"
  }
  let i = depth % vars.length()
  let j = (depth + 1) % vars.length()
  "if " +
  vars[i] +
  " " +
  vars[j] +
  " then (" +
  "λx." +
  make_if_chain(vars, depth + 1) +
  ") else (" +
  "λy." +
  make_if_chain(vars, depth + 2) +
  ")"
}

///|
/// Build a wide arithmetic chain: 1 + 2 + 3 + ... + n
fn make_wide_arithmetic(n : Int) -> String {
  let mut s = "1"
  for i = 2; i <= n; i = i + 1 {
    s = s + " + " + i.to_string()
  }
  s
}

///|
/// Build repeated lambda applications: f (f (f (... (f x) ...)))
fn make_nested_application(depth : Int) -> String {
  let mut s = "x"
  for _i = 0; _i < depth; _i = _i + 1 {
    s = "f (" + s + ")"
  }
  "λf.λx." + s
}

///|
/// Apply a single-char insert at a position, returning (new_source, edit).
fn slice(s : String, start : Int, end : Int) -> String {
  let res : Result[StringView, Error] = try? s[start:end]
  match res {
    Ok(view) => view.to_string()
    Err(_) => abort("slice out of bounds")
  }
}

///|
fn apply_char_insert(
  source : String,
  pos : Int,
  ch : String,
) -> (String, @core.Edit) {
  let before = slice(source, 0, pos)
  let after = slice(source, pos, source.length())
  let new_source = before + ch + after
  let edit = @core.Edit::insert(pos, ch.length())
  (new_source, edit)
}

///|
/// Apply a single-char replacement at a position.
fn apply_char_replace(
  source : String,
  pos : Int,
  ch : String,
) -> (String, @core.Edit) {
  let before = slice(source, 0, pos)
  let after = slice(source, pos + 1, source.length())
  let new_source = before + ch + after
  let edit = @core.Edit::replace(pos, pos + 1, pos + ch.length())
  (new_source, edit)
}

// ─── Tier 1: Large document parse ────────────────────────────────────────────

///|
/// Benchmark: Initial parse of ~200-token nested lambda expression.
test "heavy: large document - initial parse" (b : @bench.T) {
  let source = make_large_source()
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new(source)
    let result = parser.parse()
    b.keep(result)
  })
}

///|
/// Benchmark: Initial parse of 100-term arithmetic chain (~200 tokens).
test "heavy: wide arithmetic 100 terms - initial parse" (b : @bench.T) {
  let source = make_wide_arithmetic(100)
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new(source)
    let result = parser.parse()
    b.keep(result)
  })
}

///|
/// Benchmark: Initial parse of deeply nested application (depth 50).
test "heavy: nested application depth 50 - initial parse" (b : @bench.T) {
  let source = make_nested_application(50)
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new(source)
    let result = parser.parse()
    b.keep(result)
  })
}

///|
/// Benchmark: CST-level parse of large document (no AST conversion overhead).
test "heavy: large document - cst parse only" (b : @bench.T) {
  let source = make_large_source()
  let interner = @seam.Interner::new()
  let ni = @seam.NodeInterner::new()
  b.bench(fn() {
    let result = @parse.parse_cst_recover(
      source,
      interner=Some(interner),
      node_interner=Some(ni),
    ) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

// ─── Tier 2: Typing session (100 sequential edits) ──────────────────────────

///|
/// Benchmark: 100 sequential single-char edits at end of large document.
/// Simulates typing a new expression: " + x + y + z + ..."
test "heavy: typing session - 100 edits at end" (b : @bench.T) {
  let base = make_large_source()
  let chars = [
    " ", "+", " ", "x", " ", "+", " ", "y", " ", "+", " ", "z", " ", "+", " ",
    "1", " ", "+", " ", "2",
  ]
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new(base)
    let _ = parser.parse()
    let mut source = base
    for i = 0; i < 100; i = i + 1 {
      let ch = chars[i % chars.length()]
      let pos = source.length()
      let (new_source, edit) = apply_char_insert(source, pos, ch)
      let _ = parser.edit(edit, new_source)
      source = new_source
    }
    b.keep(parser.get_tree())
  })
}

///|
/// Benchmark: 100 sequential single-char edits in middle of large document.
/// Simulates inserting text inside an existing expression.
test "heavy: typing session - 100 edits in middle" (b : @bench.T) {
  let base = make_large_source()
  let mid = base.length() / 2
  let chars = [
    "x", " ", "+", " ", "y", " ", "+", " ", "1", " ", "+", " ", "2", " ", "+",
    " ", "z", " ", "+", " ",
  ]
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new(base)
    let _ = parser.parse()
    let mut source = base
    let mut insert_pos = mid
    for i = 0; i < 100; i = i + 1 {
      let ch = chars[i % chars.length()]
      let (new_source, edit) = apply_char_insert(source, insert_pos, ch)
      let _ = parser.edit(edit, new_source)
      source = new_source
      insert_pos = insert_pos + ch.length()
    }
    b.keep(parser.get_tree())
  })
}

// ─── Tier 3: Refactoring session (variable renames) ──────────────────────────

///|
/// Benchmark: 100 single-char replacements at scattered positions.
/// Simulates renaming variables throughout a large document.
test "heavy: refactoring session - 100 scattered replacements" (b : @bench.T) {
  let base = make_large_source()
  let replacements = ["x", "y", "z", "a", "b", "c", "d", "e"]
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new(base)
    let _ = parser.parse()
    let mut source = base
    let mut seed = 42
    for i = 0; i < 100; i = i + 1 {
      seed = heavy_next_seed(seed)
      let len = source.length()
      if len < 2 {
        continue i
      }
      let pos = seed.abs() % (len - 1)
      let ch = replacements[i % replacements.length()]
      let (new_source, edit) = apply_char_replace(source, pos, ch)
      let _ = parser.edit(edit, new_source)
      source = new_source
    }
    b.keep(parser.get_tree())
  })
}

// ─── Tier 4: Interner growth & sharing metrics (tests, not timed benches) ────

///|
/// Measure interner growth over a 200-edit typing session.
/// Reports sizes at key checkpoints to detect unbounded growth.
test "heavy: interner growth over 200 edits" {
  let base = make_large_source()
  let parser = @incremental.IncrementalParser::new(base)
  let _ = parser.parse()
  let initial_token_size = parser.interner_size()
  let initial_node_size = parser.node_interner_size()
  let chars = [" ", "+", " ", "x", " ", "+", " ", "1"]
  let mut source = base
  let mut max_node_size = initial_node_size
  for i = 0; i < 200; i = i + 1 {
    let ch = chars[i % chars.length()]
    let pos = source.length()
    let (new_source, edit) = apply_char_insert(source, pos, ch)
    let _ = parser.edit(edit, new_source)
    source = new_source
    let ns = parser.node_interner_size()
    if ns > max_node_size {
      max_node_size = ns
    }
  }
  let final_token_size = parser.interner_size()
  let final_node_size = parser.node_interner_size()
  // Report actual sizes for visibility
  inspect(
    (initial_token_size, final_token_size),
    content=(
      #|(21, 22)
    ),
  )
  inspect(
    (initial_node_size, final_node_size, max_node_size),
    content=(
      #|(45, 1247, 1247)
    ),
  )
  // Sanity: we actually did edits
  inspect(source.length() > base.length(), content="true")
}

///|
/// Measure structural sharing: parse the same document twice with shared interner.
/// Second parse should produce identical tree with no interner growth.
test "heavy: structural sharing on identical reparse" {
  let source = make_large_source()
  let parser = @incremental.IncrementalParser::new(source)
  let _ = parser.parse()
  let size_after_first = parser.node_interner_size()
  // Zero-length edit forces reparse with same source
  let edit = @core.Edit::insert(source.length(), 0)
  let _ = parser.edit(edit, source)
  let size_after_second = parser.node_interner_size()
  // No new nodes should be interned for identical reparse
  inspect(size_after_second <= size_after_first, content="true")
}

///|
/// Measure reuse count over a typing session.
/// Local edits at end should reuse most of the tree.
test "heavy: reuse ratio over 50 edits at end" {
  let base = make_large_source()
  let parser = @incremental.IncrementalParser::new(base)
  let _ = parser.parse()
  let chars = [" ", "+", " ", "1"]
  let mut source = base
  let mut total_reuse = 0
  let mut total_edits = 0
  for i = 0; i < 50; i = i + 1 {
    let ch = chars[i % chars.length()]
    let pos = source.length()
    let (new_source, edit) = apply_char_insert(source, pos, ch)
    let _ = parser.edit(edit, new_source)
    total_reuse = total_reuse + parser.get_last_reuse_count()
    total_edits = total_edits + 1
    source = new_source
  }
  // Should have some reuse on average (localized edits at end)
  inspect(total_reuse > 0, content="true")
  inspect(total_edits, content="50")
}

///|
/// Benchmark: Wide arithmetic 100 terms, edit near end — best case for reuse.
test "heavy: wide arithmetic 100 terms - edit near end" (b : @bench.T) {
  let source = make_wide_arithmetic(100)
  let parser = @incremental.IncrementalParser::new(source)
  let _ = parser.parse()
  let len = source.length()
  // Replace last digit: "100" -> "999"
  let new_source = slice(source, 0, len - 3) + "999"
  let edit = @core.Edit::replace(len - 3, len, len)
  b.bench(fn() {
    // Reset parser state for each iteration
    let p = @incremental.IncrementalParser::new(source)
    let _ = p.parse()
    let result = p.edit(edit, new_source)
    b.keep(result)
  })
}

///|
/// Benchmark: Full reparse of wide arithmetic 100 terms (baseline comparison).
test "heavy: wide arithmetic 100 terms - full reparse baseline" (b : @bench.T) {
  let source = make_wide_arithmetic(100)
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new(source)
    let result = parser.parse()
    b.keep(result)
  })
}
