///|
/// Parse a JSON array of {path, kind} entries. Paths are audited separately.
pub fn parse_manifest(text : String) -> Result[Array[PathEntry], InputError] {
  let value = @json.parse(text) catch {
    error =>
      return Err({ code: "INPUT_JSON", message: "Invalid JSON: \{error}", })
  }
  guard value is Array(items) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "Expected an array of path entries.",
    })
  }
  let entries : Array[PathEntry] = []
  for index, item in items {
    guard item is Object(fields) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Entry \{index} must be an object.",
      })
    }
    guard fields.get("path") is Some(String(path)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Entry \{index} must have a string path.",
      })
    }
    let kind = match fields.get("kind") {
      Some(String("file")) => File
      Some(String("directory")) => Directory
      _ =>
        return Err({
          code: "INPUT_SCHEMA",
          message: "Entry \{index} kind must be file or directory.",
        })
    }
    entries.push({ path, kind, })
  }
  Ok(entries)
}
