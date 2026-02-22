///|
test "TrackedCell dependency tracking" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 10)
  let doubled = @incr.Memo::new(rt, fn() { cell.get() * 2 })
  inspect(doubled.get(), content="20")
  cell.set(15)
  inspect(doubled.get(), content="30")
}

///|
test "TrackedCell same-value optimization" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 5)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, fn() {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = memo.get()      // compute_count = 1
  cell.set(5)             // same value — no revision bump
  let _ = memo.get()      // should NOT recompute
  inspect(compute_count, content="1")
}

///|
test "TrackedCell on_change callback" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut observed = 0
  cell.on_change(fn(v) { observed = v })
  cell.set(42)
  inspect(observed, content="42")
}

///|
test "TrackedCell get_result returns Ok" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 99)
  match cell.get_result() {
    Ok(v) => inspect(v, content="99")
    Err(_) => abort("unexpected Err")
  }
}

///|
test "TrackedCell batch integration" {
  let rt = @incr.Runtime::new()
  let a = @incr.TrackedCell::new(rt, 1)
  let b = @incr.TrackedCell::new(rt, 2)
  let sum = @incr.Memo::new(rt, fn() { a.get() + b.get() })
  inspect(sum.get(), content="3")
  rt.batch(fn() {
    a.set(10)
    b.set(20)
  })
  inspect(sum.get(), content="30")
}

///|
test "TrackedCell batch revert detection" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 0)
  let mut compute_count = 0
  let memo = @incr.Memo::new(rt, fn() {
    compute_count = compute_count + 1
    cell.get()
  })
  let _ = memo.get()      // compute_count = 1
  rt.batch(fn() {
    cell.set(99)
    cell.set(0)           // revert to original
  })
  let _ = memo.get()      // should NOT recompute (net change = 0)
  inspect(compute_count, content="1")
}

///|
test "TrackedCell as_signal interop" {
  let rt = @incr.Runtime::new()
  let cell = @incr.TrackedCell::new(rt, 7)
  let sig = cell.as_signal()
  // A Memo using the raw Signal still tracks the same dependency
  let memo = @incr.Memo::new(rt, fn() { sig.get() + 1 })
  inspect(memo.get(), content="8")
  cell.set(10)
  inspect(memo.get(), content="11")
}
