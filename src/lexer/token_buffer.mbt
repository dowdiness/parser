// Incremental token buffer for edit-aware lexing

///|
pub struct TokenBuffer {
  mut tokens : Array[@token.TokenInfo]
  mut source : String
  mut version : Int
}

///|
pub fn TokenBuffer::new(source : String) -> TokenBuffer raise TokenizationError {
  let tokens = tokenize(source)
  { tokens, source, version: 0 }
}

///|
pub fn TokenBuffer::get_tokens(self : TokenBuffer) -> Array[@token.TokenInfo] {
  self.tokens
}

///|
pub fn TokenBuffer::get_source(self : TokenBuffer) -> String {
  self.source
}

///|
pub fn TokenBuffer::get_version(self : TokenBuffer) -> Int {
  self.version
}

///|
pub fn TokenBuffer::update(
  self : TokenBuffer,
  edit : @core.Edit,
  new_source : String,
) -> Array[@token.TokenInfo] raise TokenizationError {
  let old_tokens = self.tokens
  let old_len = old_tokens.length()
  if old_len == 0 {
    let tokens = tokenize(new_source)
    self.tokens = tokens
    self.source = new_source
    self.version = self.version + 1
    return self.tokens
  }
  let eof_index = old_len - 1
  let mut left_index = find_left_index(old_tokens, edit.start)
  let mut right_index = find_right_index(old_tokens, edit.old_end())
  // Roadmap §1.3 (conservative): expand left by one token to ensure boundary edits
  // are re-lexed. This catches keyword formation (i→if), identifier splits/merges,
  // and edits that occur in leading whitespace before the first token.
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
  let replacement_tokens = tokenize_range(new_source, left_offset, right_offset)
  let new_tokens : Array[@token.TokenInfo] = []
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
      @token.TokenInfo::new(
        t.token,
        clamp_offset(t.start + delta, new_len),
        clamp_offset(t.end + delta, new_len),
      ),
    )
  }
  new_tokens.push(@token.TokenInfo::new(@token.EOF, new_len, new_len))
  self.tokens = new_tokens
  self.source = new_source
  self.version = self.version + 1
  self.tokens
}

///|
fn find_left_index(tokens : Array[@token.TokenInfo], pos : Int) -> Int {
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
fn find_right_index(tokens : Array[@token.TokenInfo], pos : Int) -> Int {
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
