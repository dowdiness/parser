///|
test "panic GreenParser::finish_node without matching start_node" {
  let parser = GreenParser::new([], "")
  parser.finish_node()
}
