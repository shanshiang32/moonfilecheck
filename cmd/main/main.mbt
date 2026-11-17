// The host handles file I/O; parsing, matching and reports stay in MoonBit.

///|
extern "js" fn read_request() -> String =
  #| () => globalThis.__moonfilecheck_request

///|
extern "js" fn emit_result(value : String) -> Unit =
  #| value => { globalThis.__moonfilecheck_result = value; }

///|
fn main {
  try {
    let request = @json.parse(read_request()[:])
    let result = match request {
      @json.Json::Array(items) => @json.Json::array(items.map(@checker.execute))
      _ => @checker.execute(request)
    }
    emit_result(result.stringify())
  } catch {
    e =>
      emit_result(
        (
          {
            "status": "error",
            "error": {
              "code": "invalid-json",
              "message": @json.to_json(e.to_string()),
            },
          } : @json.Json).stringify(),
      )
  }
}
