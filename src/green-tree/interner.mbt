///|
/// Session-scoped token intern table.
///
/// Deduplicates GreenToken objects by (kind, text): every call to
/// intern_token with the same arguments returns a structurally equal token.
///
/// Lifetime: own one Interner per parse session (e.g. per IncrementalParser).
/// The GC collects the Interner and all its tokens when the owner is dropped.
/// Not thread-safe.
///
/// Key design: two-level map (RawKind → (String → GreenToken)).
/// On the hot hit path neither the RawKind nor the String is allocated;
/// the caller's existing values are used directly as lookup keys.
pub struct Interner {
  priv tokens : @hashmap.HashMap[RawKind, @hashmap.HashMap[String, GreenToken]]
}

///|
/// Create a new empty Interner.
pub fn Interner::new() -> Interner {
  { tokens: @hashmap.HashMap::new() }
}

///|
/// Return the canonical GreenToken for (kind, text).
/// On first call for a given pair: allocates a GreenToken and stores it.
/// On subsequent calls: returns the stored object (same heap reference).
pub fn Interner::intern_token(
  self : Interner,
  kind : RawKind,
  text : String,
) -> GreenToken {
  match self.tokens.get(kind) {
    Some(inner) =>
      match inner.get(text) {
        Some(token) => token
        None => {
          let token = GreenToken::new(kind, text)
          inner.set(text, token)
          token
        }
      }
    None => {
      let token = GreenToken::new(kind, text)
      let inner : @hashmap.HashMap[String, GreenToken] = @hashmap.HashMap::new()
      inner.set(text, token)
      self.tokens.set(kind, inner)
      token
    }
  }
}

///|
/// Number of distinct (kind, text) pairs currently interned.
pub fn Interner::size(self : Interner) -> Int {
  let mut total = 0
  self.tokens.each(fn(_kind, inner) { total = total + inner.length() })
  total
}

///|
/// Clear all interned tokens. The Interner can be reused after this call,
/// e.g. when starting a new document in a long-lived language server session.
pub fn Interner::clear(self : Interner) -> Unit {
  self.tokens.clear()
}
