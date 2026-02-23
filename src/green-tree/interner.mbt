///|
/// Session-scoped token intern table.
///
/// Deduplicates GreenToken objects by (kind, text): every call to
/// intern_token with the same arguments returns the exact same heap object.
/// This means for any two tokens a, b produced through the same Interner:
///   a == b  implies  physical_equal(a, b)
///
/// Lifetime: own one Interner per parse session (e.g. per IncrementalParser).
/// The GC collects the Interner and all its tokens when the owner is dropped.
/// Not thread-safe.
pub struct Interner {
  tokens : @hashmap.HashMap[String, GreenToken]
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
  // Null-byte separator: token texts never contain \x00, so this key is
  // collision-free for all valid token content.
  let key = kind.to_string() + "\u{0000}" + text
  match self.tokens.get(key) {
    Some(token) => token
    None => {
      let token = GreenToken::new(kind, text)
      self.tokens.set(key, token)
      token
    }
  }
}

///|
/// Number of distinct (kind, text) pairs currently interned.
pub fn Interner::size(self : Interner) -> Int {
  self.tokens.length()
}

///|
/// Clear all interned tokens. The Interner can be reused after this call,
/// e.g. when starting a new document in a long-lived language server session.
pub fn Interner::clear(self : Interner) -> Unit {
  self.tokens.clear()
}
