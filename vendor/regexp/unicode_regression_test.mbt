///|
test "word boundary safely passes supplementary characters" {
  let r = @regexp.compile("\\b世界\\b")
  inspect(r.execute("😀 世界").matched(), content="true")
  inspect(r.execute("字世界").matched(), content="false")
}

///|
test "Unicode word class includes supplementary letters and combining marks" {
  let r = @regexp.compile("^\\w+$")
  inspect(r.execute("世界𐐀a\u0301").matched(), content="true")
  inspect(r.execute("😀").matched(), content="false")
}
