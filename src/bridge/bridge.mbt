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
    Some(String("check")) => {
      guard fields.get("manifest_text") is Some(String(text)) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing manifest text.",
        )
      }
      match @moonportcheck.parse_manifest(text) {
        Err(e) => error_response(format, 2, e.code, e.message)
        Ok(entries) =>
          report_response(
            format,
            @moonportcheck.audit_with_options(
              entries,
              @moonportcheck.default_audit_options(),
            ),
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
      guard fields.get("scan_issues") is Some(Array(raw_issues)) else {
        return error_response(
          format, 2, "INPUT_SCHEMA", "Missing scan issues array.",
        )
      }
      let base = @moonportcheck.audit_with_options(
        entries,
        @moonportcheck.default_audit_options(),
      )
      let issues : Array[@moonportcheck.ScanIssue] = []
      for item in raw_issues {
        guard item is Object(issue) else {
          return error_response(
            format, 2, "INPUT_SCHEMA", "Scan issue must be an object.",
          )
        }
        guard issue.get("code") is Some(String(code)) else {
          return error_response(
            format, 2, "INPUT_SCHEMA", "Scan issue requires a code.",
          )
        }
        guard issue.get("path") is Some(String(path)) else {
          return error_response(
            format, 2, "INPUT_SCHEMA", "Scan issue requires a path.",
          )
        }
        guard issue.get("message") is Some(String(message)) else {
          return error_response(
            format, 2, "INPUT_SCHEMA", "Scan issue requires a message.",
          )
        }
        issues.push({ code, path, message, })
      }
      let report = @moonportcheck.with_scan_issues(base, issues)
      report_response(format, report)
    }
    _ => error_response(format, 2, "ARGUMENT_ERROR", "Unknown request mode.")
  }
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
