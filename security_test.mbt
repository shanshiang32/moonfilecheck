///|
test "resource limits reject expensive regex and oversized substitutions" {
  for
    rules in [
      "check: $(=a{4294967295})", "check: $(=(a{1000}){1000})", "check: $(=(?:){1000000})",
    ] {
    guard @moonfilecheck.execute({ "rules": @json.to_json(rules), "input": "a" })
      is { "status": "error", .. } else {
      fail("unsafe expansion accepted")
    }
  }
  let long = StringBuilder()
  for _ in 0..<8193 {
    long.write_char('a')
  }
  guard @moonfilecheck.execute({
      "rules": "check: $V",
      "input": "a",
      "variables": { "V": @json.to_json(long.to_string()) },
    })
    is { "status": "error", .. } else {
    fail("oversized variable accepted")
  }
}

///|
test "positions survive unordered rewind and supplementary characters" {
  let r = @moonfilecheck.check(
    "unordered: end\nunordered: 世界\ncheck: done", "😀 世界\r\nend\ndone",
  )
  assert_true(r.passed)
  assert_eq(r.matches[0].input_line, 2)
  assert_eq(r.matches[1].input_line, 1)
  assert_eq(r.matches[1].input_column, 3)
  assert_eq(r.matches[2].input_line, 3)
}

///|
test "diagnostic truncation preserves surrogate pairs" {
  let input = StringBuilder()
  for _ in 0..<239 {
    input.write_char('a')
  }
  input.write_string("😀 end")
  let r = @moonfilecheck.check("check: missing", input.to_string())
  assert_false(r.passed)
  assert_eq(r.diagnostic.unwrap().excerpt.length(), 239)
}
