///|
test "reject huge and nested counted repetition before expansion" {
  for pattern in ["a{4294967295}", "(?:a{1000}){1000}", "(?:){1000000}"] {
    let rejected = try {
      let _ = @regexp.compile(pattern[:])
      false
    } catch {
      _ => true
    }
    inspect(rejected, content="true")
  }
  inspect(@regexp.compile("a{2,4}").execute("aaa").matched(), content="true")
}
