// Matching state machine adapted from bytecodealliance/filecheck/checker.rs.
// Copyright The Cranelift Project Developers; Apache-2.0 WITH LLVM-exception.

///|
fn next_line(text : String, pos : Int32) -> Int32 {
  match text[pos:].find("\n") {
    Some(n) => pos + n + 1
    None => text.length()
  }
}

///|
fn location(text : String, offset : Int32) -> (Int32, Int32) {
  location_from(text, 0, offset, 1, 1)
}

///|
fn location_from(
  text : String,
  start : Int32,
  offset : Int32,
  initial_line : Int32,
  initial_column : Int32,
) -> (Int32, Int32) {
  let mut line = initial_line
  let mut column = initial_column
  for c in text[start:offset].iter() {
    if c == '\n' {
      line = line + 1
      column = 1
    } else {
      column = column + 1
    }
  }
  (line, column)
}

///|
fn diagnostic(
  text : String,
  d : Directive,
  offset : Int32,
  code : String,
  message : String,
) -> Diagnostic {
  let (input_line, input_column) = location(text, offset)
  let start = match text[:offset].rev_find("\n") {
    Some(n) => n + 1
    None => 0
  }
  let end = next_line(text, offset)
  let mut excerpt_end = if end - start > 240 { start + 240 } else { end }
  if excerpt_end < text.length() &&
    text[excerpt_end] >= 0xDC00 &&
    text[excerpt_end] <= 0xDFFF {
    excerpt_end = excerpt_end - 1
  }
  let excerpt = text[start:excerpt_end].trim_end().to_owned()
  {
    code,
    message,
    rule_line: d.line,
    input_line,
    input_column,
    pattern: d.pattern.source,
    excerpt,
  }
}

///|
fn unordered_begin(
  pattern : Pattern,
  vars : Map[String, Variable],
  ordered : Int32,
) -> Int32 {
  let mut start = ordered
  for name in pattern.refs {
    if vars.get(name) is Some(v) && v.offset > start {
      start = v.offset
    }
  }
  start
}

///|
fn negative_hit(
  rx : @regexp.Regexp,
  input : String,
  start : Int32,
  end : Int32,
) -> Int32? {
  if start > end {
    return None
  }
  let result = rx.execute(input[start:end])
  if result.matched() {
    Some(start + result.before().length())
  } else {
    None
  }
}

///|
/// Match input without mutating this checker. Variables are reset on every call.
pub fn Checker::check(
  self : Checker,
  input : String,
  variables~ : Map[String, String] = Map([]),
) -> Report raise CheckError {
  if input.length() > 8388608 {
    raise fail("resource-limit", 0, "input exceeds eight million UTF-16 units")
  }
  validate_unicode(input)
  if variables.length() > 10000 {
    raise fail("resource-limit", 0, "too many external variables")
  }
  let vars : Map[String, Variable] = Map([])
  for name, value in variables {
    if name.length() > 4096 || value.length() > 8192 {
      raise fail("resource-limit", 0, "external variable exceeds length limit")
    }
    validate_unicode(value)
    if name.is_empty() || var_end(name, 0) != name.length() {
      raise fail("syntax", 0, "invalid external variable name")
    }
    vars[name] = { value, is_regex: false, offset: 0, }
  }
  let captured : Map[String, String] = Map([])
  let matches : Array[MatchSpan] = []
  let pending : Array[(Directive, Int32, @regexp.Regexp)] = []
  let mut ordered = 0
  let mut furthest = 0
  let mut error : Diagnostic? = None
  let mut location_offset = 0
  let mut location_line = 1
  let mut location_column = 1
  for d in self.directives {
    if d.kind == "regex" {
      vars[d.name] = { value: d.regex, is_regex: true, offset: 0, }
      continue
    }
    let rx = d.pattern.resolve(vars, d.line)
    if d.kind == "not" {
      pending.push((d, unordered_begin(d.pattern, vars, ordered), rx))
      continue
    }
    let (start, end) = match d.kind {
      "sameln" => (furthest, next_line(input, furthest))
      "nextln" => {
        let b = next_line(input, furthest)
        (b, next_line(input, b))
      }
      "unordered" => (unordered_begin(d.pattern, vars, ordered), input.length())
      _ => (furthest, input.length())
    }
    let result = rx.execute(input[start:end])
    if !result.matched() {
      error = Some(
        diagnostic(
          input,
          d,
          start,
          "missing-match",
          "expected " + d.kind + " pattern was not found",
        ),
      )
      break
    }
    let begin = start + result.before().length()
    let finish = begin + result.get(0).unwrap().length()
    for name in d.pattern.defs {
      let value = match result.groups().get("mfc_" + name) {
        Some(v) => v.to_owned()
        None => ""
      }
      vars[name] = { value, is_regex: false, offset: finish, }
      captured[name] = value
    }
    // Ordered matches scan each prefix only once. Unordered matches can rewind.
    let (input_line, input_column) = if begin >= location_offset {
      location_from(
        input, location_offset, begin, location_line, location_column,
      )
    } else {
      location(input, begin)
    }
    location_offset = begin
    location_line = input_line
    location_column = input_column
    matches.push({
      directive: d.kind,
      rule_line: d.line,
      start: begin,
      end: finish,
      input_line,
      input_column,
    })
    if d.kind == "unordered" {
      if finish > furthest {
        furthest = finish
      }
    } else {
      ordered = finish
      furthest = finish
      for (negative, from, neg_rx) in pending {
        if negative_hit(neg_rx, input, from, begin) is Some(hit) {
          error = Some(
            diagnostic(
              input, negative, hit, "forbidden-match", "forbidden pattern was found",
            ),
          )
          break
        }
      }
      pending.clear()
      if error is Some(_) {
        break
      }
    }
  }
  if error is None {
    for (negative, from, neg_rx) in pending {
      if negative_hit(neg_rx, input, from, input.length()) is Some(hit) {
        error = Some(
          diagnostic(
            input, negative, hit, "forbidden-match", "forbidden pattern was found",
          ),
        )
        break
      }
    }
  }
  {
    passed: error is None,
    directives: self.directives.length(),
    matches,
    variables: captured,
    diagnostic: error,
  }
}

///|
/// Convenience API for a single check. The library accepts empty checkers.
pub fn check(
  rules : String,
  input : String,
  variables~ : Map[String, String] = Map([]),
) -> Report raise CheckError {
  Checker::parse(rules).check(input, variables~)
}
