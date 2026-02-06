// Detailed performance benchmarks for incremental parser
// Measures scaling behavior and incremental-state overhead
// Run with: moon bench --package parser --release

///|
/// Benchmark: Parse scaling - small input (5 tokens)
test "parse scaling - small (5 tokens)" (b : @bench.T) {
  b.bench(fn() {
    let result = @parse.parse_tree("1 + 2") catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
/// Benchmark: Parse scaling - medium input (15 tokens)
test "parse scaling - medium (15 tokens)" (b : @bench.T) {
  b.bench(fn() {
    let result = @parse.parse_tree("λf.λx.if f x then x + 1 else x - 1") catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Parse scaling - large input (30+ tokens)
test "parse scaling - large (30+ tokens)" (b : @bench.T) {
  b.bench(fn() {
    let result = @parse.parse_tree(
      "λf.λx.if f x then (λy.y + 1) x else (λz.z - 1) (f x)",
    ) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental vs Full - tiny edit at start
test "incremental vs full - edit at start" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("λf.λx.if f x then x + 1 else x - 1")
    let _ = parser.parse()
    let edit = @edit.Edit::replace(0, 1, 1)
    let result = parser.edit(edit, "\\f.λx.if f x then x + 1 else x - 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental vs Full - tiny edit at end
test "incremental vs full - edit at end" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("λf.λx.if f x then x + 1 else x - 1")
    let _ = parser.parse()
    let edit = @edit.Edit::replace(32, 33, 33)
    let result = parser.edit(edit, "λf.λx.if f x then x + 1 else x - 2")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental vs Full - edit in middle
test "incremental vs full - edit in middle" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("λf.λx.if f x then x + 1 else x - 1")
    let _ = parser.parse()
    let edit = @edit.Edit::replace(14, 15, 15)
    let result = parser.edit(edit, "λf.λx.if f x then y + 1 else x - 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Sequential edits - typing simulation
test "sequential edits - typing simulation" (b : @bench.T) {
  b.bench(fn() {
    // Simulate typing by making progressive edits
    let parser1 = @incremental.IncrementalParser::new("x")
    let _ = parser1.parse()
    let edit1 = @edit.Edit::insert(1, 4)
    let result = parser1.edit(edit1, "x + 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Sequential edits - backspace simulation
test "sequential edits - backspace simulation" (b : @bench.T) {
  b.bench(fn() {
    // Simulate backspacing by deleting text
    let parser = @incremental.IncrementalParser::new("x + 1")
    let _ = parser.parse()
    let edit = @edit.Edit::delete(2, 5) // Delete " + 1"
    let result = parser.edit(edit, "x")
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental state baseline - repeated parsing
test "incremental state baseline - repeated parsing" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("λx.x")
    let _ = parser.parse()

    // Make edit
    let edit = @edit.Edit::insert(4, 8)
    let _ = parser.edit(edit, "λx.x + 1")

    // Undo edit (should hit cache ideally)
    let edit2 = @edit.Edit::delete(4, 8)
    let _ = parser.edit(edit2, "λx.x")

  })
}

///|
/// Benchmark: Incremental state baseline - similar expressions
test "incremental state baseline - similar expressions" (b : @bench.T) {
  b.bench(fn() {
    let parser1 = @incremental.IncrementalParser::new("x + 1")
    let result1 = parser1.parse()
    let parser2 = @incremental.IncrementalParser::new("x + 2")
    let result2 = parser2.parse()
    b.keep((result1, result2))
  })
}

///|
/// Benchmark: Damage tracking - localized damage
test "damage tracking - localized damage" (b : @bench.T) {
  b.bench(fn() {
    let edit = @edit.Edit::replace(4, 5, 5)
    let damage = @incremental.DamageTracker::new(edit)
    let tree = @parse.parse_tree("x + 1") catch { _ => abort("benchmark failed") }
    damage.expand_for_tree(tree)
    b.keep(damage)
  })
}

///|
/// Benchmark: Damage tracking - widespread damage
test "damage tracking - widespread damage" (b : @bench.T) {
  b.bench(fn() {
    let edit = @edit.Edit::replace(0, 1, 1)
    let damage = @incremental.DamageTracker::new(edit)
    let tree = @parse.parse_tree("λf.λx.if f x then x + 1 else x - 1") catch {
      _ => abort("benchmark failed")
    }
    damage.expand_for_tree(tree)
    b.keep(damage)
  })
}

///|
/// Benchmark: Position adjustment after edit
test "position adjustment after edit" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("λf.λx.f x")
    let tree = parser.parse()
    let edit = @edit.Edit::insert(7, 4)
    let adjusted = parser.adjust_tree_positions(tree, edit)
    b.keep(adjusted)
  })
}

///|
/// Benchmark: CRDT operations - nested structure
test "crdt operations - nested structure" (b : @bench.T) {
  b.bench(fn() {
    let ast = @parse.parse_tree("λf.λx.if f x then x + 1 else x - 1") catch {
      _ => abort("benchmark failed")
    }
    let crdt = @crdt.ast_to_crdt(ast)
    let source = @crdt.crdt_to_source(crdt)
    b.keep(source)
  })
}

///|
/// Benchmark: CRDT operations - round trip
test "crdt operations - round trip" (b : @bench.T) {
  b.bench(fn() {
    let original = "λf.λx.f (f x)"
    let ast = @parse.parse_tree(original) catch { _ => abort("benchmark failed") }
    let crdt = @crdt.ast_to_crdt(ast)
    let reconstructed = @crdt.crdt_to_source(crdt)
    let ast2 = @parse.parse_tree(reconstructed) catch {
      _ => abort("benchmark failed")
    }
    b.keep(ast2)
  })
}

///|
/// Benchmark: Memory pressure - large document
test "memory pressure - large document" (b : @bench.T) {
  b.bench(fn() {
    // Build a moderately complex expression (simpler to avoid parsing issues)
    let large_expr = "λf.λx.if f x then (λy.y + 1) x else (λz.z - 1) (f x)"
    let parser = @incremental.IncrementalParser::new(large_expr)
    let _ = parser.parse()

    // Make small edit - change first variable
    let edit = @edit.Edit::replace(3, 4, 4) // Replace 'f' with 'g'
    let new_expr = "λg.λx.if g x then (λy.y + 1) x else (λz.z - 1) (g x)"
    let result = parser.edit(edit, new_expr)
    b.keep(result)
  })
}

///|
/// Benchmark: Worst case - invalidate entire cache
test "worst case - full invalidation" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("λf.λx.if f x then x + 1 else x - 1")
    let _ = parser.parse()

    // Change at start affects everything (λ → \)
    let edit = @edit.Edit::replace(0, 1, 1)
    let result = parser.edit(edit, "\\f.λx.if f x then x + 1 else x - 1")
    b.keep(result)
  })
}

///|
/// Benchmark: Best case - cosmetic change
test "best case - cosmetic change" (b : @bench.T) {
  b.bench(fn() {
    let parser = @incremental.IncrementalParser::new("x + 1")
    let _ = parser.parse()

    // Change just the constant
    let edit = @edit.Edit::replace(4, 5, 5)
    let result = parser.edit(edit, "x + 2")
    b.keep(result)
  })
}

// --- Phase 1: Incremental Lexer Benchmarks (110 tokens) ---
//
// Generates "1 + 2 + 3 + ... + 55" (110 tokens: 55 integers + 54 plus + EOF, 263 chars).
// Compares full tokenize() vs TokenBuffer.update() for single-char edits.
// Each incremental benchmark includes TokenBuffer::new (which calls tokenize internally),
// so the measured overhead beyond full tokenize reflects the update cost.

///|
fn make_token_source() -> String {
  let mut s = "1"
  for i = 2; i <= 55; i = i + 1 {
    s = s + " + " + i.to_string()
  }
  s
}

///|
fn make_token_source_replace(target : Int) -> String {
  let mut s = if target == 1 { "99" } else { "1" }
  for i = 2; i <= 55; i = i + 1 {
    s = s + " + " + (if i == target { "99" } else { i.to_string() })
  }
  s
}

///|
/// Benchmark: Full tokenization of 110-token input (baseline for incremental comparison)
test "phase1: full tokenize - 110 tokens" (b : @bench.T) {
  let source = make_token_source()
  b.bench(fn() {
    let result = @lexer.tokenize(source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental tokenize - replace "1" at start with "99"
/// Edit: position [0,1) → [0,2), adds 1 char
test "phase1: incremental tokenize - edit at start (110 tokens)" (b : @bench.T) {
  let source = make_token_source()
  let new_source = make_token_source_replace(1)
  let edit = @edit.Edit::replace(0, 1, 2)
  b.bench(fn() {
    let buf = @lexer.TokenBuffer::new(source) catch { _ => abort("benchmark failed") }
    let result = buf.update(edit, new_source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental tokenize - replace "28" at middle with "99"
/// Edit: position [126,128) → [126,128), same-length replacement
test "phase1: incremental tokenize - edit in middle (110 tokens)" (b : @bench.T) {
  let source = make_token_source()
  let new_source = make_token_source_replace(28)
  let edit = @edit.Edit::replace(126, 128, 128)
  b.bench(fn() {
    let buf = @lexer.TokenBuffer::new(source) catch { _ => abort("benchmark failed") }
    let result = buf.update(edit, new_source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Incremental tokenize - replace "55" at end with "99"
/// Edit: position [261,263) → [261,263), same-length replacement
test "phase1: incremental tokenize - edit at end (110 tokens)" (b : @bench.T) {
  let source = make_token_source()
  let new_source = make_token_source_replace(55)
  let edit = @edit.Edit::replace(261, 263, 263)
  b.bench(fn() {
    let buf = @lexer.TokenBuffer::new(source) catch { _ => abort("benchmark failed") }
    let result = buf.update(edit, new_source) catch {
      _ => abort("benchmark failed")
    }
    b.keep(result)
  })
}

///|
/// Benchmark: Full re-tokenize of edited source (comparison: what you'd pay without incremental)
test "phase1: full re-tokenize after edit - 110 tokens" (b : @bench.T) {
  let new_source = make_token_source_replace(28)
  b.bench(fn() {
    let result = @lexer.tokenize(new_source) catch { _ => abort("benchmark failed") }
    b.keep(result)
  })
}
