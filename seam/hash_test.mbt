///|
test "string_hash is deterministic" {
  inspect(string_hash("hello") == string_hash("hello"), content="true")
}

///|
test "string_hash differs for different strings" {
  inspect(string_hash("a") == string_hash("b"), content="false")
}

///|
test "combine_hash is nonzero for nonzero inputs" {
  inspect(combine_hash(1, 2) != 0, content="true")
}
