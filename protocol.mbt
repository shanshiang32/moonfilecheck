///|
fn require_string(
  obj : Map[String, @json.Json],
  name : String,
) -> String raise CheckError {
  match obj.get(name) {
    Some(@json.Json::String(value)) => value
    _ => raise fail("invalid-request", 0, "expected string field: " + name)
  }
}

///|
/// JSON boundary for CLI, automation and browser hosts. Never raises.
pub fn execute(request : @json.Json) -> @json.Json {
  try {
    guard request is @json.Json::Object(obj) else {
      raise fail("invalid-request", 0, "request must be an object")
    }
    let rules = require_string(obj, "rules")
    let input = require_string(obj, "input")
    let allow_empty = match obj.get("allow_empty") {
      None | Some(@json.Json::False) => false
      Some(@json.Json::True) => true
      _ => raise fail("invalid-request", 0, "allow_empty must be boolean")
    }
    let variables : Map[String, String] = Map([])
    match obj.get("variables") {
      None => ()
      Some(@json.Json::Object(values)) =>
        for name, value in values {
          guard value is @json.Json::String(text) else {
            raise fail("invalid-request", 0, "variable values must be strings")
          }
          variables[name] = text
        }
      _ => raise fail("invalid-request", 0, "variables must be an object")
    }
    let checker = Checker::parse(rules, allow_empty~)
    let report = checker.check(input, variables~)
    {
      "status": if report.passed {
        "pass"
      } else {
        "fail"
      },
      "report": report.to_json(),
    }
  } catch {
    CheckError(code, line, message) =>
      {
        "status": "error",
        "error": {
          "code": @json.to_json(code),
          "rule_line": @json.to_json(line),
          "message": @json.to_json(message),
        },
      }
  }
}
