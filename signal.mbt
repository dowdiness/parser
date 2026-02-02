///|
/// An externally-set input value. The T: Eq constraint enables
/// same-value optimization (skip revision bump if value unchanged).
pub struct Signal[T] {
  rt : Runtime
  cell_id : CellId
  mut value : T
  mut pending_value : T?
  durability : Durability
}

///|
/// Create a new Signal with Low durability.
pub fn[T] Signal::new(rt : Runtime, initial : T) -> Signal[T] {
  Signal::new_with_durability(rt, initial, Low)
}

///|
/// Create a new Signal with the specified durability.
pub fn[T] Signal::new_with_durability(
  rt : Runtime,
  initial : T,
  durability : Durability,
) -> Signal[T] {
  let cell_id = rt.alloc_cell_id()
  let meta = CellMeta::new_input(cell_id, durability)
  rt.register_cell(meta)
  { rt, cell_id, value: initial, pending_value: None, durability }
}

///|
/// Read the signal value and record a dependency in the current tracking context.
pub fn[T] Signal::get(self : Signal[T]) -> T {
  self.rt.record_dependency(self.cell_id)
  self.value
}

///|
/// Set the signal value. If the new value equals the old value (via Eq),
/// this is a no-op — no revision bump occurs.
/// During a batch, writes go to pending_value. At batch end, only values
/// that differ from the current value produce a change.
pub fn[T : Eq] Signal::set(self : Signal[T], new_value : T) -> Unit {
  if self.rt.batch_depth > 0 {
    self.set_batch(new_value)
  } else {
    if self.value == new_value {
      return
    }
    self.set_unconditional(new_value)
  }
}

///|
/// Set the signal value unconditionally, always bumping the revision.
/// During a batch, the value is stored as pending and committed at batch end.
pub fn[T] Signal::set_unconditional(
  self : Signal[T],
  new_value : T,
) -> Unit {
  if self.rt.batch_depth > 0 {
    self.set_batch_unconditional(new_value)
  } else {
    self.value = new_value
    self.rt.bump_revision(self.durability)
    let meta = self.rt.get_cell(self.cell_id)
    meta.changed_at = self.rt.current_revision
    meta.verified_at = self.rt.current_revision
  }
}

///|
/// Store a pending value during a batch (with Eq check).
fn[T : Eq] Signal::set_batch(self : Signal[T], new_value : T) -> Unit {
  // Compare against current pending value (if any) or actual value
  let current = match self.pending_value {
    Some(pv) => pv
    None => self.value
  }
  if current == new_value {
    return
  }
  self.pending_value = Some(new_value)
  // Register commit closure if not already registered
  let meta = self.rt.get_cell(self.cell_id)
  if meta.commit_pending is None {
    meta.commit_pending = Some(fn() { self.commit() })
    self.rt.record_batch_signal(self.cell_id)
  }
  self.rt.bump_revision(self.durability)
}

///|
/// Store a pending value during a batch (unconditional).
fn[T] Signal::set_batch_unconditional(self : Signal[T], new_value : T) -> Unit {
  self.pending_value = Some(new_value)
  let meta = self.rt.get_cell(self.cell_id)
  if meta.commit_pending is None {
    meta.commit_pending = Some(fn() { self.commit_unconditional() })
    self.rt.record_batch_signal(self.cell_id)
  }
  self.rt.bump_revision(self.durability)
}

///|
/// Commit the pending value. Returns true if the value actually changed.
fn[T : Eq] Signal::commit(self : Signal[T]) -> Bool {
  match self.pending_value {
    None => false
    Some(pv) => {
      let changed = self.value != pv
      if changed {
        self.value = pv
      }
      self.pending_value = None
      changed
    }
  }
}

///|
/// Commit the pending value unconditionally. Always returns true if there
/// is a pending value (no equality check).
fn[T] Signal::commit_unconditional(self : Signal[T]) -> Bool {
  match self.pending_value {
    None => false
    Some(pv) => {
      self.value = pv
      self.pending_value = None
      true
    }
  }
}
