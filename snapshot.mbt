///|
/// A persisted scan state: unique, sorted entries plus the effective scope,
/// completeness and scan issues of the scan that produced them. Snapshots never
/// store file content, timestamps or host-specific absolute paths.
pub struct Snapshot {
  profile : String
  complete : Bool
  scope : Array[String]
  entries : Array[PathEntry]
  scan_issues : Array[ScanIssue]
} derive(Eq, Debug)

///|
pub extend Snapshot with Eq::{equal, not_equal}

///|
pub extend Snapshot with @debug.Debug::{to_repr}

///|
/// Snapshot entries sort by path then kind so the persisted document is stable
/// across scans and executable backends.
fn snapshot_entry_order(a : PathEntry, b : PathEntry) -> Int {
  let order = ordinal_compare(a.path, b.path)
  if order != 0 {
    return order
  }
  ordinal_compare(source_kind_name(a.kind), source_kind_name(b.kind))
}

///|
/// Build a canonical snapshot from scanned entries. Duplicated identical
/// entries collapse, a path with conflicting kinds is rejected, and the scope
/// is validated and normalized. A snapshot with no scan issues is complete.
pub fn build_snapshot(
  entries : Array[PathEntry],
  scan_issues : Array[ScanIssue],
  scope : Array[String],
) -> Result[Snapshot, InputError] {
  let validated = match parse_scope(scope) {
    Err(error) => return Err(error)
    Ok(scope) => scope
  }
  let by_path : Map[String, EntryKind] = Map([])
  for entry in entries {
    match by_path.get(entry.path) {
      Some(existing) =>
        if existing != entry.kind {
          return Err({
            code: "INPUT_SCHEMA",
            message: "Snapshot path has conflicting kinds.",
          })
        }
      None => by_path[entry.path] = entry.kind
    }
  }
  let unique : Array[PathEntry] = []
  for path in sorted_keys(by_path) {
    unique.push({ path, kind: by_path[path], })
  }
  let issues = scan_issues.copy()
  sort_scan_issues(issues)
  Ok({
    profile: "portable-windows-v1",
    complete: issues.is_empty(),
    scope: effective_scope_patterns(validated),
    entries: unique,
    scan_issues: issues,
  })
}

///|
/// Parse a snapshot document. The document must be canonical: entries sorted
/// and unique, scope normalized, scan issues well-formed, and only known
/// fields present. Corrupted or non-canonical input is rejected.
pub fn parse_snapshot(text : String) -> Result[Snapshot, InputError] {
  let value = @json.parse(text) catch {
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "Invalid JSON in the snapshot.",
      })
  }
  guard value is Object(fields) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The snapshot must be a JSON object.",
    })
  }
  match fields.get("format") {
    Some(String("moonportcheck-snapshot")) => ()
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "Unsupported snapshot format.",
      })
  }
  match fields.get("version") {
    Some(Number(n, ..)) if n == 1.0 => ()
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "Unsupported snapshot version.",
      })
  }
  guard fields.get("profile") is Some(String(profile)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The snapshot requires a string profile.",
    })
  }
  let complete = match fields.get("complete") {
    Some(True) => true
    Some(False) => false
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The snapshot requires a boolean complete.",
      })
  }
  let scope = match fields.get("scope") {
    Some(Array(items)) =>
      match collect_snapshot_strings(items, "scope") {
        Err(error) => return Err(error)
        Ok(strings) => strings
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The snapshot requires a scope array.",
      })
  }
  let normalized_scope = match parse_scope(scope) {
    Err(error) => return Err(error)
    Ok(parsed) => effective_scope_patterns(parsed)
  }
  let entries = match fields.get("entries") {
    Some(Array(items)) =>
      match parse_snapshot_entries(items) {
        Err(error) => return Err(error)
        Ok(entries) => entries
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The snapshot requires an entries array.",
      })
  }
  let issues = match fields.get("scan_issues") {
    Some(Array(items)) =>
      match parse_snapshot_issues(items) {
        Err(error) => return Err(error)
        Ok(issues) => issues
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The snapshot requires a scan_issues array.",
      })
  }
  for name in fields.keys() {
    match name {
      "format"
      | "version"
      | "profile"
      | "complete"
      | "scope"
      | "entries"
      | "scan_issues" => ()
      _ =>
        return Err({
          code: "INPUT_SCHEMA",
          message: "Unknown snapshot field: " + name,
        })
    }
  }
  sort_scan_issues(issues)
  Ok({
    profile,
    complete,
    scope: normalized_scope,
    entries,
    scan_issues: issues,
  })
}

///|
/// Stable schema 1 snapshot serialization with fixed field order.
pub fn render_snapshot_json(snapshot : Snapshot) -> String {
  let entries = snapshot.entries.copy()
  entries.sort_by(snapshot_entry_order)
  let issues = snapshot.scan_issues.copy()
  sort_scan_issues(issues)
  let scope = snapshot.scope.copy()
  scope.sort_by(ordinal_compare)
  "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":" +
  quote(snapshot.profile) +
  ",\"complete\":" +
  snapshot.complete.to_json().stringify() +
  ",\"scope\":" +
  json_strings(scope) +
  ",\"entries\":[" +
  entries
  .map(entry => {
    "{\"path\":" +
    quote(entry.path) +
    ",\"kind\":" +
    quote(source_kind_name(entry.kind)) +
    "}"
  })
  .join(",") +
  "],\"scan_issues\":[" +
  issues
  .map(issue => {
    "{\"code\":" +
    quote(issue.code) +
    ",\"path\":" +
    quote(issue.path) +
    ",\"message\":" +
    quote(issue.message) +
    "}"
  })
  .join(",") +
  "]}"
}

///|
fn collect_snapshot_strings(
  items : Array[Json],
  field : String,
) -> Result[Array[String], InputError] {
  let strings : Array[String] = []
  for item in items {
    guard item is String(text) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot " + field + " must contain only strings.",
      })
    }
    strings.push(text)
  }
  Ok(strings)
}

///|
/// Parse snapshot entries enforcing strict ascending order and uniqueness.
fn parse_snapshot_entries(
  items : Array[Json],
) -> Result[Array[PathEntry], InputError] {
  let entries : Array[PathEntry] = []
  for index, item in items {
    guard item is Object(fields) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot entry " + index.to_string() + " must be an object.",
      })
    }
    guard fields.get("path") is Some(String(path)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot entry " +
        index.to_string() +
        " must have a string path.",
      })
    }
    let kind = match fields.get("kind") {
      Some(String("file")) => File
      Some(String("directory")) => Directory
      _ =>
        return Err({
          code: "INPUT_SCHEMA",
          message: "Snapshot entry " +
          index.to_string() +
          " kind must be file or directory.",
        })
    }
    let entry = { path, kind, }
    if !entries.is_empty() &&
      snapshot_entry_order(entries[entries.length() - 1], entry) >= 0 {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot entries must be sorted and unique.",
      })
    }
    entries.push(entry)
  }
  Ok(entries)
}

///|
fn parse_snapshot_issues(
  items : Array[Json],
) -> Result[Array[ScanIssue], InputError] {
  let issues : Array[ScanIssue] = []
  for index, item in items {
    guard item is Object(fields) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot scan issue " +
        index.to_string() +
        " must be an object.",
      })
    }
    guard fields.get("code") is Some(String(code)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot scan issue " +
        index.to_string() +
        " requires a code.",
      })
    }
    guard fields.get("path") is Some(String(path)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot scan issue " +
        index.to_string() +
        " requires a path.",
      })
    }
    guard fields.get("message") is Some(String(message)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot scan issue " +
        index.to_string() +
        " requires a message.",
      })
    }
    issues.push({ code, path, message, })
  }
  Ok(issues)
}
