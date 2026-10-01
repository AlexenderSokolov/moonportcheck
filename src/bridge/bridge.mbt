///|
/// String-only boundary between Node filesystem metadata and MoonBit policy.
pub fn run_request(request : String) -> String {
  let value = @json.parse(request) catch {
    _ =>
      return error_response(
        "json", 2, "INPUT_JSON", "Invalid bridge request JSON.",
      )
  }
  guard value is Object(fields) else {
    return error_response(
      "json", 2, "INPUT_SCHEMA", "Bridge request must be an object.",
    )
  }
  let format = match fields.get("format") {
    Some(String("text")) => "text"
    Some(String("json")) => "json"
    _ =>
      return error_response(
        "json", 2, "ARGUMENT_ERROR", "Format must be text or json.",
      )
  }
  match fields.get("mode") {
    Some(String("rules")) => rules_response(format, @moonportcheck.rules())
    Some(String("explain")) => {
      guard fields.get("code") is Some(String(code)) else {
        return error_response(format, 2, "INPUT_SCHEMA", "Missing rule code.")
      }
      match @moonportcheck.explain(code) {
        None => error_response(format, 2, "RULE_UNKNOWN", "Unknown rule code.")
        Some(rule) => rules_response(format, [rule])
      }
    }
    Some(String("error")) => {
      guard fields.get("code") is Some(String(code)) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing host error code.",
        )
      }
      guard fields.get("message") is Some(String(message)) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing host error message.",
        )
      }
      let exit_code = match fields.get("exit_code") {
        Some(Number(n, ..)) if n == 3.0 => 3
        Some(Number(n, ..)) if n == 2.0 => 2
        _ =>
          return error_response(
            format, 2, "INPUT_SCHEMA", "Host errors must exit 2 or 3.",
          )
      }
      error_response(format, exit_code, code, message)
    }
    Some(String("scope")) => {
      // Validate the config and CLI exclusions and return the effective,
      // deduplicated pattern list the host may use to prune a real scan.
      let patterns : Array[String] = []
      match fields.get("config_text") {
        None => ()
        Some(String(text)) =>
          match parse_config(text) {
            Err(error) =>
              return error_response(format, 2, error.code, error.message)
            Ok(configured) =>
              for pattern in configured {
                patterns.push(pattern)
              }
          }
        Some(_) =>
          return error_response(
            format, 2, "INPUT_SCHEMA", "Config text must be a string or omitted.",
          )
      }
      match fields.get("cli_exclude") {
        None => ()
        Some(Array(items)) =>
          match collect_patterns(items) {
            Err(error) =>
              return error_response(format, 2, error.code, error.message)
            Ok(cli) =>
              for pattern in cli {
                patterns.push(pattern)
              }
          }
        Some(_) =>
          return error_response(
            format, 2, "INPUT_SCHEMA", "CLI exclusions must be an array of strings.",
          )
      }
      match @moonportcheck.parse_scope(patterns) {
        Err(error) => error_response(format, 2, error.code, error.message)
        Ok(scope) =>
          response(
            0,
            "{\"patterns\":" +
            json_string_array(@moonportcheck.effective_scope_patterns(scope)) +
            "}",
          )
      }
    }
    Some(String("excluded")) => {
      // Single-path host query used only to decide whether a real directory
      // can be pruned; the same MoonBit matcher decides every exclusion.
      let patterns = match fields.get("patterns") {
        Some(Array(items)) =>
          match collect_patterns(items) {
            Err(error) =>
              return error_response(format, 2, error.code, error.message)
            Ok(patterns) => patterns
          }
        Some(_) =>
          return error_response(
            format, 2, "INPUT_SCHEMA", "Exclusion patterns must be an array of strings.",
          )
        None =>
          return error_response(
            format, 2, "INPUT_SCHEMA", "Missing exclusion patterns.",
          )
      }
      guard fields.get("path") is Some(String(path)) else {
        return error_response(format, 2, "INPUT_SCHEMA", "Missing path.")
      }
      let kind = match fields.get("kind") {
        Some(String("file")) => @moonportcheck.File
        Some(String("directory")) => @moonportcheck.Directory
        _ =>
          return error_response(
            format, 2, "INPUT_SCHEMA", "Kind must be file or directory.",
          )
      }
      match @moonportcheck.parse_scope(patterns) {
        Err(error) => error_response(format, 2, error.code, error.message)
        Ok(scope) =>
          response(
            0,
            @moonportcheck.entry_excluded(scope, { path, kind, })
            .to_json()
            .stringify(),
          )
      }
    }
    Some(String("check")) => {
      guard fields.get("manifest_text") is Some(String(text)) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing manifest text.",
        )
      }
      // check accepts either an original array manifest or a snapshot
      // document; classify by the parsed top-level JSON value.
      let value = @json.parse(text) catch {
        _ =>
          return error_response(
            format, 2, "INPUT_JSON", "Invalid JSON in the check input.",
          )
      }
      match value {
        Array(_) =>
          match @moonportcheck.parse_manifest(text) {
            Err(e) => error_response(format, 2, e.code, e.message)
            Ok(entries) =>
              match scope_of(fields) {
                Err(error) =>
                  error_response(format, 2, error.code, error.message)
                Ok(scope) =>
                  report_response(
                    format,
                    @moonportcheck.audit_with_exclusions(
                      entries,
                      @moonportcheck.default_audit_options(),
                      scope,
                    ),
                  )
              }
          }
        Object(_) =>
          match @moonportcheck.parse_snapshot(text) {
            Err(e) => error_response(format, 2, e.code, e.message)
            Ok(snapshot) => {
              let extra = match scope_of(fields) {
                Err(error) =>
                  return error_response(format, 2, error.code, error.message)
                Ok(scope) => @moonportcheck.effective_scope_patterns(scope)
              }
              match @moonportcheck.audit_snapshot(snapshot, extra) {
                Err(error) =>
                  error_response(format, 2, error.code, error.message)
                Ok(report) => report_response(format, report)
              }
            }
          }
        _ =>
          error_response(
            format, 2, "INPUT_SCHEMA", "The check input must be a manifest array or a snapshot document.",
          )
      }
    }
    Some(String("scan")) => {
      guard fields.get("entries") is Some(raw_entries) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing scan entries.",
        )
      }
      let entries = match
        @moonportcheck.parse_manifest(raw_entries.stringify()) {
        Err(e) => return error_response(format, 2, e.code, e.message)
        Ok(entries) => entries
      }
      let issues = match parse_scan_issues(fields) {
        Err(error) =>
          return error_response(format, 2, error.code, error.message)
        Ok(issues) => issues
      }
      let base = match scope_of(fields) {
        Err(error) =>
          return error_response(format, 2, error.code, error.message)
        Ok(scope) =>
          @moonportcheck.audit_with_exclusions(
            entries,
            @moonportcheck.default_audit_options(),
            scope,
          )
      }
      let report = @moonportcheck.with_scan_issues(base, issues)
      report_response(format, report)
    }
    Some(String("snapshot")) => {
      // Build and serialize a canonical snapshot from a scanned tree. The
      // document is the only output; completeness drives the exit code.
      guard fields.get("entries") is Some(raw_entries) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing scan entries.",
        )
      }
      let entries = match
        @moonportcheck.parse_manifest(raw_entries.stringify()) {
        Err(e) => return error_response(format, 2, e.code, e.message)
        Ok(entries) => entries
      }
      let issues = match parse_scan_issues(fields) {
        Err(error) =>
          return error_response(format, 2, error.code, error.message)
        Ok(issues) => issues
      }
      let scope = match scope_of(fields) {
        Err(error) =>
          return error_response(format, 2, error.code, error.message)
        Ok(scope) => @moonportcheck.effective_scope_patterns(scope)
      }
      match @moonportcheck.build_snapshot(entries, issues, scope) {
        Err(error) => error_response(format, 2, error.code, error.message)
        Ok(snapshot) =>
          response(
            if snapshot.complete {
              0
            } else {
              3
            },
            @moonportcheck.render_snapshot_json(snapshot),
          )
      }
    }
    Some(String("diff")) => {
      // Compare two snapshot documents. Exit codes: 2 for a malformed document
      // or mismatched scopes, 3 when either input is incomplete, 1 when there
      // are changes and 0 when there are none.
      guard fields.get("before_text") is Some(String(before_text)) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing the before snapshot text.",
        )
      }
      guard fields.get("after_text") is Some(String(after_text)) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing the after snapshot text.",
        )
      }
      let before = match @moonportcheck.parse_snapshot(before_text) {
        Err(e) => return error_response(format, 2, e.code, e.message)
        Ok(snapshot) => snapshot
      }
      let after = match @moonportcheck.parse_snapshot(after_text) {
        Err(e) => return error_response(format, 2, e.code, e.message)
        Ok(snapshot) => snapshot
      }
      let diff = match @moonportcheck.diff_snapshots(before, after) {
        Err(e) => return error_response(format, 2, e.code, e.message)
        Ok(diff) => diff
      }
      let output = match format {
        "json" => @moonportcheck.render_snapshot_diff_json(diff)
        _ => @moonportcheck.render_snapshot_diff_text(diff)
      }
      let exit = if diff.complete == false {
        3
      } else if diff.changes.length() > 0 {
        1
      } else {
        0
      }
      response(exit, output)
    }
    _ => error_response(format, 2, "ARGUMENT_ERROR", "Unknown request mode.")
  }
}

///|
/// Parse the shared scan_issues request field into ScanIssue records.
fn parse_scan_issues(
  fields : Map[String, Json],
) -> Result[Array[@moonportcheck.ScanIssue], @moonportcheck.InputError] {
  guard fields.get("scan_issues") is Some(Array(items)) else {
    return Err({ code: "INPUT_SCHEMA", message: "Missing scan issues array.", })
  }
  let issues : Array[@moonportcheck.ScanIssue] = []
  for item in items {
    guard item is Object(issue) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Scan issue must be an object.",
      })
    }
    guard issue.get("code") is Some(String(code)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Scan issue requires a code.",
      })
    }
    guard issue.get("path") is Some(String(path)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Scan issue requires a path.",
      })
    }
    guard issue.get("message") is Some(String(message)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Scan issue requires a message.",
      })
    }
    issues.push({ code, path, message, })
  }
  Ok(issues)
}

///|
/// Build the effective scope from an optional exclude_patterns array.
fn scope_of(
  fields : Map[String, Json],
) -> Result[@moonportcheck.ExclusionScope, @moonportcheck.InputError] {
  match fields.get("exclude_patterns") {
    None => @moonportcheck.parse_scope([])
    Some(Array(items)) =>
      match collect_patterns(items) {
        Err(error) => Err(error)
        Ok(patterns) => @moonportcheck.parse_scope(patterns)
      }
    Some(_) =>
      Err({
        code: "INPUT_SCHEMA",
        message: "Exclude patterns must be an array of strings.",
      })
  }
}

///|
fn collect_patterns(
  items : Array[Json],
) -> Result[Array[String], @moonportcheck.InputError] {
  let patterns : Array[String] = []
  for item in items {
    guard item is String(pattern) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Exclusion patterns must be strings.",
      })
    }
    patterns.push(pattern)
  }
  Ok(patterns)
}

///|
/// Versioned configuration: {"schema_version": 1, "exclude": [String...]}.
/// Unknown fields and a missing or unsupported schema version are input errors.
fn parse_config(
  text : String,
) -> Result[Array[String], @moonportcheck.InputError] {
  let value = @json.parse(text) catch {
    _ =>
      return Err({
        code: "INPUT_CONFIG",
        message: "Invalid JSON in the configuration file.",
      })
  }
  guard value is Object(fields) else {
    return Err({
      code: "INPUT_CONFIG",
      message: "The configuration must be a JSON object.",
    })
  }
  let mut schema_version : Int = 0
  let mut exclude : Array[String] = []
  for name in fields.keys() {
    match name {
      "schema_version" =>
        match fields.get("schema_version") {
          Some(Number(n, ..)) if n == 1.0 => schema_version = 1
          _ =>
            return Err({
              code: "INPUT_CONFIG",
              message: "Configuration schema_version must be 1.",
            })
        }
      "exclude" =>
        match fields.get("exclude") {
          Some(Array(items)) =>
            match collect_patterns(items) {
              Ok(patterns) => {
                exclude = patterns
                ()
              }
              Err(_) =>
                return Err({
                  code: "INPUT_CONFIG",
                  message: "Configuration exclude must contain only strings.",
                })
            }
          Some(_) =>
            return Err({
              code: "INPUT_CONFIG",
              message: "Configuration exclude must be an array of strings.",
            })
          None => ()
        }
      _ =>
        return Err({
          code: "INPUT_CONFIG",
          message: "Unknown configuration field: " + name,
        })
    }
  }
  if schema_version != 1 {
    return Err({
      code: "INPUT_CONFIG",
      message: "Configuration schema_version is required.",
    })
  }
  Ok(exclude)
}

///|
fn json_string_array(items : Array[String]) -> String {
  "[" + items.map(item => item.to_json().stringify()).join(",") + "]"
}

///|
fn response(exit_code : Int, output : String) -> String {
  "{\"exit_code\":\{exit_code},\"output\":" + output.to_json().stringify() + "}"
}

///|
fn rules_response(
  format : String,
  items : Array[@moonportcheck.RuleInfo],
) -> String {
  response(
    0,
    if format == "json" {
      @moonportcheck.render_rules_json(items)
    } else {
      @moonportcheck.render_rules_text(items)
    },
  )
}

///|
fn error_response(
  format : String,
  exit_code : Int,
  code : String,
  message : String,
) -> String {
  let output = if format == "json" {
    "{\"schema_version\":2,\"profile\":\"portable-windows-v1\",\"complete\":false,\"error\":{\"code\":" +
    code.to_json().stringify() +
    ",\"message\":" +
    message.to_json().stringify() +
    "}}"
  } else {
    "MoonPortCheck error [" +
    code.to_json().stringify() +
    "]: " +
    message.to_json().stringify()
  }
  response(exit_code, output)
}

///|
fn report_response(
  format : String,
  report : @moonportcheck.DetailedReport,
) -> String {
  let exit_code = if !report.complete {
    3
  } else if report.diagnostics.is_empty() {
    0
  } else {
    1
  }
  let output = if format == "json" {
    @moonportcheck.render_detailed_json(report)
  } else {
    @moonportcheck.render_detailed_text(report)
  }
  response(exit_code, output)
}
