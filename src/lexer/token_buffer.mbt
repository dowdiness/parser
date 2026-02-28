// Generic incremental token buffer for edit-aware lexing.
// T is the language-specific token type.
//
// Contract: tokenize_fn must always append an EOF sentinel as the last element.
// TokenBuffer::update relies on this when re-lexing a range: the last element
// of tokenize_fn(slice) is skipped during offset-adjustment.

///|
pub struct TokenBuffer[T] {
  priv tokenize_fn : (String) -> Array[@core.TokenInfo[T]] raise TokenizationError
  priv eof_token : T
  mut tokens : Array[@core.TokenInfo[T]]
  mut source : String
  mut version : Int
}

///|
pub fn[T] TokenBuffer::new(
  source : String,
  tokenize_fn~ : (String) -> Array[@core.TokenInfo[T]] raise TokenizationError,
  eof_token~ : T,
) -> TokenBuffer[T] raise TokenizationError {
  let tokens = tokenize_fn(source)
  { tokenize_fn, eof_token, tokens, source, version: 0 }
}

///|
pub fn[T] TokenBuffer::get_tokens(
  self : TokenBuffer[T],
) -> Array[@core.TokenInfo[T]] {
  self.tokens
}

///|
pub fn[T] TokenBuffer::get_source(self : TokenBuffer[T]) -> String {
  self.source
}

///|
pub fn[T] TokenBuffer::get_version(self : TokenBuffer[T]) -> Int {
  self.version
}

///|
pub fn[T] TokenBuffer::update(
  self : TokenBuffer[T],
  edit : @core.Edit,
  new_source : String,
) -> Array[@core.TokenInfo[T]] raise TokenizationError {
  let old_tokens = self.tokens
  let old_len = old_tokens.length()
  if old_len == 0 {
    let tokens = (self.tokenize_fn)(new_source)
    self.tokens = tokens
    self.source = new_source
    self.version = self.version + 1
    return self.tokens
  }
  let eof_index = old_len - 1
  let mut left_index = find_left_index(old_tokens, edit.start)
  let mut right_index = find_right_index(old_tokens, edit.old_end())
  // Conservative: expand left by one token to catch boundary edits.
  if left_index > 0 {
    left_index = left_index - 1
  }
  if left_index > right_index {
    let tmp = right_index
    right_index = left_index
    left_index = tmp
  }
  if right_index < eof_index {
    right_index = right_index + 1
  }
  let mut left_offset_old = old_tokens[left_index].start
  if edit.start < left_offset_old {
    left_offset_old = edit.start
  }
  let mut right_offset_old = old_tokens[right_index].end
  if edit.old_end() > right_offset_old {
    right_offset_old = edit.old_end()
  }
  let left_offset_new = map_start_pos(left_offset_old, edit)
  let right_offset_new = map_end_pos(right_offset_old, edit)
  let new_len = new_source.length()
  let left_offset = clamp_offset(left_offset_new, new_len)
  let mut right_offset = clamp_offset(right_offset_new, new_len)
  if right_offset < left_offset {
    right_offset = left_offset
  }
  let replacement_tokens = self.tokenize_range_impl(
    new_source, left_offset, right_offset,
  )
  let new_tokens : Array[@core.TokenInfo[T]] = []
  for i = 0; i < left_index; i = i + 1 {
    new_tokens.push(old_tokens[i])
  }
  for token_info in replacement_tokens {
    new_tokens.push(token_info)
  }
  let delta = edit.delta()
  for i = right_index + 1; i < eof_index; i = i + 1 {
    let t = old_tokens[i]
    new_tokens.push(
      @core.TokenInfo::new(
        t.token,
        clamp_offset(t.start + delta, new_len),
        clamp_offset(t.end + delta, new_len),
      ),
    )
  }
  new_tokens.push(@core.TokenInfo::new(self.eof_token, new_len, new_len))
  self.tokens = new_tokens
  self.source = new_source
  self.version = self.version + 1
  self.tokens
}

///|
/// Re-lex a range of source. Tokenize the slice and offset-adjust results.
/// Skips the trailing EOF that tokenize_fn appends by contract (last element).
fn[T] TokenBuffer::tokenize_range_impl(
  self : TokenBuffer[T],
  source : String,
  start : Int,
  end : Int,
) -> Array[@core.TokenInfo[T]] raise TokenizationError {
  let slice = source[start:end] catch {
      _ => raise TokenizationError("Invalid range")
    }
  let slice_tokens = (self.tokenize_fn)(slice.to_string())
  // tokenize_fn contract: EOF is always last — skip it.
  let result : Array[@core.TokenInfo[T]] = []
  for i = 0; i < slice_tokens.length() - 1; i = i + 1 {
    let t = slice_tokens[i]
    result.push(@core.TokenInfo::new(t.token, t.start + start, t.end + start))
  }
  result
}

///|
fn[T] find_left_index(tokens : Array[@core.TokenInfo[T]], pos : Int) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  for i = 0; i < len; i = i + 1 {
    if tokens[i].end >= pos {
      return i
    }
  }
  len - 1
}

///|
fn[T] find_right_index(tokens : Array[@core.TokenInfo[T]], pos : Int) -> Int {
  let len = tokens.length()
  if len == 0 {
    return 0
  }
  for i = len - 1; i >= 0; i = i - 1 {
    if tokens[i].start <= pos {
      return i
    }
  }
  0
}

///|
fn map_start_pos(pos : Int, edit : @core.Edit) -> Int {
  if pos <= edit.start {
    pos
  } else if pos >= edit.old_end() {
    pos + edit.delta()
  } else {
    edit.start
  }
}

///|
fn map_end_pos(pos : Int, edit : @core.Edit) -> Int {
  if pos < edit.start {
    pos
  } else if pos >= edit.old_end() {
    pos + edit.delta()
  } else {
    edit.new_end()
  }
}

///|
fn clamp_offset(pos : Int, length : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > length {
    length
  } else {
    pos
  }
}
