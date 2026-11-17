// Adapted from bytecodealliance/filecheck src/pattern.rs.
// Copyright The Cranelift Project Developers; Apache-2.0 WITH LLVM-exception.

///|
fn regex_end(s : String, start : Int32) -> Int32 {
  let mut depth = 0
  let mut state = 0 // 0 normal, 1 curly, 2 charset first, 3 negated first, 4 charset
  let mut escaped = false
  for i = start; i < s.length(); i = i + 1 {
    let c = s[i]
    if escaped {
      escaped = false
      continue
    }
    if c == 92 {
      escaped = true
      continue
    }
    match state {
      0 =>
        match c {
          91 => state = 2
          123 => state = 1
          40 => depth = depth + 1
          41 if depth > 0 => depth = depth - 1
          41 | 125 => return i
          _ => ()
        }
      1 => if c == 125 { state = 0 }
      2 => state = if c == 94 { 3 } else { 4 }
      3 => state = 4
      _ => if c == 93 { state = 0 }
    }
  }
  s.length()
}

///|
fn parse_pattern(source : String, line : Int32) -> Pattern raise CheckError {
  let s = source.trim().to_owned()
  if s.length() > 4096 {
    raise fail("resource-limit", line, "pattern exceeds 4096 UTF-16 units")
  }
  let parts : Array[Part] = []
  let defs : Array[String] = []
  let refs : Array[String] = []
  let mut i = 0
  while i < s.length() {
    if s[i] != 36 {
      let start = i
      while i < s.length() && s[i] != 36 {
        i = i + 1
      }
      parts.push(Text(s[start:i].to_owned()))
      continue
    }
    if i + 1 < s.length() && s[i + 1] == 36 {
      parts.push(Text("$"))
      i = i + 2
      continue
    }
    let end = var_end(s, i + 1)
    if end > i + 1 {
      let name = s[i + 1:end].to_owned()
      if defs.contains(name) {
        raise fail(
          "backreference",
          line,
          "variable cannot reference its definition in the same pattern: " +
          name,
        )
      }
      refs.push(name)
      parts.push(Ref(name))
      i = end
      continue
    }
    if i + 1 >= s.length() || s[i + 1] != 40 {
      raise fail("syntax", line, "use $$ to match a literal dollar sign")
    }
    let end = var_end(s, i + 2)
    let name = s[i + 2:end].to_owned()
    if end >= s.length() {
      raise fail("syntax", line, "unterminated $( expression")
    }
    if s[end] == 41 {
      if name.is_empty() {
        parts.push(Text(""))
      } else {
        if defs.contains(name) {
          raise fail(
            "backreference",
            line,
            "same-pattern backreference: " + name,
          )
        }
        refs.push(name)
        parts.push(Ref(name))
      }
      i = end + 1
      continue
    }
    if s[end] != 61 {
      raise fail("syntax", line, "expected = or ) after variable name")
    }
    if !name.is_empty() {
      if name[0] >= 48 && name[0] <= 57 {
        raise fail(
          "invalid-capture-name", line, "capture names cannot start with a digit (Rust regex compatibility)",
        )
      }
      if defs.contains(name) {
        raise fail("duplicate-definition", line, "duplicate variable: " + name)
      }
      defs.push(name)
    }
    if end + 1 < s.length() && s[end + 1] == 36 {
      let re = var_end(s, end + 2)
      if re == end + 2 || re >= s.length() || s[re] != 41 || name.is_empty() {
        raise fail("syntax", line, "expected $(name=$variable)")
      }
      let reference = s[end + 2:re].to_owned()
      if defs.contains(reference) {
        raise fail(
          "backreference",
          line,
          "same-pattern backreference: " + reference,
        )
      }
      refs.push(reference)
      parts.push(CaptureRef(name, reference))
      i = re + 1
    } else {
      let re = regex_end(s, end + 1)
      if re >= s.length() || s[re] != 41 {
        raise fail("syntax", line, "missing ) after regular expression")
      }
      let rx = s[end + 1:re].to_owned()
      let _ = compile_regex(rx, line)
      if name.is_empty() {
        parts.push(Raw(rx))
      } else {
        parts.push(Capture(name, rx))
      }
      i = re + 1
    }
  }
  { source: s, parts, defs, refs, }
}

///|
fn lookup(
  vars : Map[String, Variable],
  name : String,
  line : Int32,
) -> Variable raise CheckError {
  match vars.get(name) {
    Some(v) => v
    None =>
      raise fail("undefined-variable", line, "undefined variable: $" + name)
  }
}

///|
fn alphanumeric(s : String, first : Bool) -> Bool {
  let c = if first { s.iter().next() } else { s.rev_iter().next() }
  match c {
    None => false
    Some(ch) if ch.is_ascii() => ch.is_ascii_alphabetic() || ch.is_ascii_digit()
    Some(ch) =>
      // Unicode category L/N includes non-Latin identifiers and decimal digits.
      @regexp.compile("^[\\p{L}\\p{N}]$").execute(ch.to_string()[:]).matched() catch {
        _ => false
      }
  }
}

///|
fn Pattern::resolve(
  self : Pattern,
  vars : Map[String, Variable],
  line : Int32,
) -> @regexp.Regexp raise CheckError {
  let out = StringBuilder()
  match self.parts.get(0) {
    Some(Text(s)) if alphanumeric(s, true) => out.write_string("\\b")
    _ => ()
  }
  let mut expanded_length = 4 // reserve both optional word boundaries
  for part in self.parts {
    let fragment = match part {
      Text(s) => escape_regex(s)
      Raw(rx) => "(?:" + rx + ")"
      Ref(name) => {
        let v = lookup(vars, name, line)
        if v.is_regex {
          "(?:" + v.value + ")"
        } else {
          escape_regex(v.value)
        }
      }
      Capture(name, rx) => "(?<mfc_" + name + ">" + rx + ")"
      CaptureRef(name, reference) => {
        let v = lookup(vars, reference, line)
        let rx = if v.is_regex { v.value } else { escape_regex(v.value) }
        "(?<mfc_" + name + ">" + rx + ")"
      }
    }
    expanded_length = expanded_length + fragment.length()
    if expanded_length > 8192 {
      raise fail(
        "resource-limit", line, "expanded regex exceeds 8192 UTF-16 units",
      )
    }
    out.write_string(fragment)
  }
  match self.parts.last() {
    Some(Text(s)) if alphanumeric(s, false) => out.write_string("\\b")
    _ => ()
  }
  compile_regex(out.to_string(), line)
}

///|
/// Parse directives embedded in arbitrary source text.
pub fn Checker::parse(
  source : String,
  allow_empty~ : Bool = true,
) -> Checker raise CheckError {
  if source.length() > 1048576 {
    raise fail("resource-limit", 0, "rules exceed one million UTF-16 units")
  }
  validate_unicode(source)
  let scanner = compile_regex(
    "\\b(check|sameln|nextln|unordered|not|regex):[ \\t]+(.*)", 0,
  )
  let directives : Array[Directive] = []
  let mut index = 0
  for view in source.split("\n") {
    index = index + 1
    let result = scanner.execute(view)
    if !result.matched() {
      continue
    }
    let kind = result.get(1).unwrap().to_owned()
    let rest = result.get(2).unwrap().to_owned()
    let line = index
    if directives.length() >= 10000 {
      raise fail("resource-limit", line, "too many directives")
    }
    if kind == "regex" {
      let end = var_end(rest, 0)
      if end == 0 || end >= rest.length() || rest[end] != 61 {
        raise fail("syntax", line, "expected regex: NAME=expression")
      }
      let rx = rest[end + 1:].trim_end().to_owned()
      let _ = compile_regex(rx, line)
      directives.push({
        kind,
        line,
        pattern: parse_pattern("", line),
        name: rest[:end].to_owned(),
        regex: rx,
      })
    } else {
      let pattern = parse_pattern(rest, line)
      if kind == "not" && !pattern.defs.is_empty() {
        raise fail("negative-capture", line, "not: cannot define variables")
      }
      directives.push({ kind, line, pattern, name: "", regex: "", })
    }
  }
  if !allow_empty && directives.is_empty() {
    raise fail(
      "empty-rules", 0, "no directives found; use --allow-empty to accept this",
    )
  }
  { directives, }
}
