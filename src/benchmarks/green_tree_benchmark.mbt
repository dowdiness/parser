// Focused microbenchmarks for green-tree construction and equality/hash fast paths.
// Run with: moon bench --package dowdiness/parser/benchmarks --release

///|
fn make_ident_token(text : String) -> @green_tree.GreenToken {
  @green_tree.GreenToken::new(@green_tree.RawKind(9), text)
}

///|
fn make_flat_ident_node(count : Int) -> @green_tree.GreenNode {
  let children : Array[@green_tree.GreenElement] = []
  for i = 0; i < count; i = i + 1 {
    children.push(
      @green_tree.GreenElement::Token(make_ident_token("x" + i.to_string())),
    )
  }
  @green_tree.GreenNode::new(@green_tree.RawKind(20), children)
}

///|
/// Benchmark: GreenToken constructor (includes token hash computation).
test "green-tree - token constructor" (b : @bench.T) {
  b.bench(fn() {
    let t = make_ident_token("identifier_123")
    b.keep(t)
  })
}

///|
/// Benchmark: GreenNode constructor over prebuilt children (hash fold cost).
test "green-tree - node constructor from 32 children" (b : @bench.T) {
  let children : Array[@green_tree.GreenElement] = []
  for i = 0; i < 32; i = i + 1 {
    children.push(
      @green_tree.GreenElement::Token(make_ident_token("x" + i.to_string())),
    )
  }
  b.bench(fn() {
    let n = @green_tree.GreenNode::new(@green_tree.RawKind(20), children)
    b.keep(n)
  })
}

///|
/// Benchmark: Equality on identical trees (hash check + deep structural walk).
test "green-tree - equality identical 32 children" (b : @bench.T) {
  let left = make_flat_ident_node(32)
  let right = make_flat_ident_node(32)
  b.bench(fn() {
    let same = left == right
    b.keep(same)
  })
}

///|
/// Benchmark: Equality on different trees (hash fast path should fail early).
test "green-tree - equality mismatch hash fast path" (b : @bench.T) {
  let left = make_flat_ident_node(32)
  let children : Array[@green_tree.GreenElement] = []
  for i = 0; i < 32; i = i + 1 {
    let text = if i == 31 { "changed_tail" } else { "x" + i.to_string() }
    children.push(@green_tree.GreenElement::Token(make_ident_token(text)))
  }
  let right = @green_tree.GreenNode::new(@green_tree.RawKind(20), children)
  b.bench(fn() {
    let same = left == right
    b.keep(same)
  })
}
