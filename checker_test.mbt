///|
test "ordered matches and word boundaries" {
  assert_true(@moonfilecheck.check("check: one\ncheck: two", "one two").passed)
  assert_false(@moonfilecheck.check("check: one\ncheck: two", "two one").passed)
  assert_false(@moonfilecheck.check("check: one", "someone").passed)
  assert_true(@moonfilecheck.check("check: one$()", "onetwo").passed)
}

///|
test "captured register is reused literally" {
  let rules = "regex: REG=r[0-9]+\ncheck: load $(v=$REG), input\nnextln: add $v, 1"
  let report = @moonfilecheck.check(rules, "load r17, input\nadd r17, 1")
  assert_true(report.passed)
  assert_eq(report.variables.get("v"), Some("r17"))
  assert_false(
    @moonfilecheck.check(rules, "load r17, input\nadd r18, 1").passed,
  )
}

///|
test "same and next line" {
  assert_true(@moonfilecheck.check("check: a\nsameln: b", "a b").passed)
  assert_false(@moonfilecheck.check("check: a\nsameln: b", "a\nb").passed)
  assert_true(@moonfilecheck.check("check: a\nnextln: b", "a\nb").passed)
  assert_false(@moonfilecheck.check("check: a\nnextln: b", "a\n\nb").passed)
}

///|
test "negative range ends at the next ordered match" {
  assert_true(
    @moonfilecheck.check(
      "check: start\nnot: error\ncheck: end", "start end error",
    ).passed,
  )
  let r = @moonfilecheck.check(
    "check: start\nnot: error\ncheck: end", "start error end",
  )
  assert_false(r.passed)
  assert_eq(r.diagnostic.unwrap().code, "forbidden-match")
  assert_false(
    @moonfilecheck.check("check: start\nnot: error", "start error").passed,
  )
}

///|
test "unordered matches overlap but cannot cross a barrier" {
  let rules = "unordered: one\nunordered: two\ncheck: three"
  assert_true(@moonfilecheck.check(rules, "two one three").passed)
  assert_false(@moonfilecheck.check(rules, "two three one").passed)
  assert_true(
    @moonfilecheck.check("unordered: same\nunordered: same", "same").passed,
  )
}

///|
test "unordered references follow defining match" {
  let rules = "regex: V=v[0-9]+\nunordered: $(a=$V) = load\nunordered: use $a"
  assert_true(@moonfilecheck.check(rules, "v2 = load\nuse v2").passed)
  assert_false(@moonfilecheck.check(rules, "use v2\nv2 = load").passed)
}

///|
test "reusable checker does not leak captures" {
  let c = @moonfilecheck.Checker::parse("check: $(v=[a-z]+)\nnextln: $v")
  assert_true(c.check("abc\nabc").passed)
  assert_true(c.check("xyz\nxyz").passed)
}

///|
test "external variables are literals" {
  assert_true(
    @moonfilecheck.check("check: $V", "a.b", variables={ "V": "a.b" }).passed,
  )
  assert_false(
    @moonfilecheck.check("check: $V", "axb", variables={ "V": "a.b" }).passed,
  )
}

///|
test "CRLF unicode and non BMP locations" {
  let r = @moonfilecheck.check(
    "check: 世界\r\nnextln: done", "😀 世界\r\ndone",
  )
  assert_true(r.passed)
  assert_eq(r.matches[0].input_column, 3)
  assert_eq(r.matches[1].input_line, 2)
  let r = @moonfilecheck.check("check: 𐐀\ncheck: end", "end 𐐀")
  assert_false(r.passed)
  assert_eq(r.matches[0].start, 4)
  assert_eq(r.matches[0].end, 6)
}

///|
test "protocol rejects empty and invalid rules" {
  let r = @moonfilecheck.execute({ "rules": "no directives", "input": "x" })
  guard r is { "status": "error", .. } else { fail("expected error") }
  let r = @moonfilecheck.execute({ "rules": "check: $unknown", "input": "x" })
  guard r is { "status": "error", .. } else { fail("expected error") }
}
