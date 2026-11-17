///|
/// An invalid rule or unsupported expression. Offsets in reports use UTF-16.
pub(all) suberror CheckError {
  CheckError(String, Int32, String)
}

///|
/// A successfully matched positive directive. Lines/columns are one-based.
#derive(ToJson)
pub(all) struct MatchSpan {
  directive : String
  rule_line : Int32
  start : Int32
  end : Int32
  input_line : Int32
  input_column : Int32
}

///|
pub extend MatchSpan with @json.ToJson::{to_json}

///|
#derive(ToJson)
pub(all) struct Diagnostic {
  code : String
  message : String
  rule_line : Int32
  input_line : Int32
  input_column : Int32
  pattern : String
  excerpt : String
}

///|
pub extend Diagnostic with @json.ToJson::{to_json}

///|
#derive(ToJson)
pub(all) struct Report {
  passed : Bool
  directives : Int32
  matches : Array[MatchSpan]
  variables : Map[String, String]
  diagnostic : Diagnostic?
}

///|
pub extend Report with @json.ToJson::{to_json}

///|
priv enum Part {
  Text(String)
  Raw(String)
  Ref(String)
  Capture(String, String)
  CaptureRef(String, String)
}

///|
priv struct Pattern {
  source : String
  parts : Array[Part]
  defs : Array[String]
  refs : Array[String]
}

///|
priv struct Directive {
  kind : String
  line : Int32
  pattern : Pattern
  name : String
  regex : String
}

///|
priv struct Variable {
  value : String
  is_regex : Bool
  offset : Int32
}

///|
/// A reusable parsed ruleset. Matching state is local to each check.
pub struct Checker {
  priv directives : Array[Directive]
}

///|
fn fail(code : String, line : Int32, message : String) -> CheckError {
  CheckError(code, line, message)
}

///|
fn validate_unicode(text : String) -> Unit raise CheckError {
  let mut i = 0
  while i < text.length() {
    let c = text[i]
    if c >= 0xD800 && c <= 0xDBFF {
      if i + 1 >= text.length() || text[i + 1] < 0xDC00 || text[i + 1] > 0xDFFF {
        raise fail("invalid-unicode", 0, "unpaired UTF-16 high surrogate")
      }
      i = i + 2
    } else if c >= 0xDC00 && c <= 0xDFFF {
      raise fail("invalid-unicode", 0, "unpaired UTF-16 low surrogate")
    } else {
      i = i + 1
    }
  }
}

///|
fn is_var(c : UInt16) -> Bool {
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  (c >= 48 && c <= 57) ||
  c == 95
}

///|
fn var_end(s : String, start : Int32) -> Int32 {
  let mut i = start
  while i < s.length() && is_var(s[i]) {
    i = i + 1
  }
  i
}

///|
fn escape_regex(s : String) -> String {
  let out = StringBuilder()
  for c in s.iter() {
    if "\\.+*?()|[]{}^$".contains_char(c) {
      out.write_char('\\')
    }
    out.write_char(c)
  }
  out.to_string()
}

///|
fn compile_regex(
  source : String,
  line : Int32,
) -> @regexp.Regexp raise CheckError {
  // Rust regex does not support backreferences or look-around. Reject these
  // rather than enabling regexp.mbt's potentially exponential backreferences.
  if source.length() > 8192 {
    raise fail(
      "resource-limit", line, "expanded regex exceeds 8192 UTF-16 units",
    )
  }
  let mut escaped = false
  for c in source.iter() {
    if escaped {
      if c.is_ascii_digit() || c == 'k' || c == 'g' {
        raise fail("unsupported-regex", line, "backreferences are unsupported")
      }
      if !c.is_ascii() ||
        (c.is_ascii_alphabetic() && !"bBdDsSwWnrtfvuUpP".contains_char(c)) {
        raise fail("unsupported-regex", line, "unsupported regex escape")
      }
      escaped = false
    } else if c == '\\' {
      escaped = true
    }
  }
  // regexp.mbt spells Rust's (?P<name>...) as (?<name>...). Translate only
  // actual group openings, never escaped text or character-class contents.
  let normalized = StringBuilder()
  let mut i = 0
  let mut in_class = false
  let mut depth = 0
  let mut alternations = 0
  while i < source.length() {
    if source[i] == 92 && i + 1 < source.length() {
      let escaped_char = source.get_char(i + 1).unwrap()
      normalized.write_char('\\')
      normalized.write_char(escaped_char)
      i = i + 1 + (if escaped_char.is_bmp() { 1 } else { 2 })
      continue
    }
    if source[i] == 91 {
      in_class = true
    }
    if source[i] == 93 {
      in_class = false
    }
    if !in_class {
      if source[i] == 40 {
        depth = depth + 1
      }
      if source[i] == 41 {
        depth = depth - 1
      }
      if source[i] == 124 {
        alternations = alternations + 1
      }
      if depth > 64 || alternations > 256 {
        raise fail(
          "resource-limit", line, "regex nesting or alternation limit exceeded",
        )
      }
    }
    if !in_class && source[i:].has_prefix("(?P<") {
      normalized.write_string("(?<")
      i = i + 4
    } else {
      let ch = source.get_char(i).unwrap()
      normalized.write_char(ch)
      i = i + (if ch.is_bmp() { 1 } else { 2 })
    }
  }
  @regexp.compile(normalized.to_string()[:], flags="m") catch {
    e => raise fail("invalid-regex", line, e.to_string())
  }
}
