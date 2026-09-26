///|
/// Serialize the report with stable field and diagnostic ordering.
pub fn render_json(report : Report) -> String {
  let diagnostics = report.diagnostics.copy()
  sort_diagnostics(diagnostics)
  let rendered = diagnostics.map(d => {
    let paths = d.paths.copy()
    paths.sort_by(ordinal_compare)
    "{\"code\":" +
    quote(d.code) +
    ",\"severity\":" +
    quote(d.severity) +
    ",\"paths\":" +
    json_strings(paths) +
    ",\"occurrences\":\{d.occurrences},\"message\":" +
    quote(d.message) +
    "}"
  })
  let s = report.summary
  "{\"schema_version\":\{report.schema_version},\"profile\":" +
  quote(report.profile) +
  ",\"source\":" +
  quote(report.source) +
  ",\"complete\":\{report.complete}," +
  "\"summary\":{\"entries\":\{s.entries},\"files\":\{s.files},\"directories\":\{s.directories}," +
  "\"diagnostic_groups\":\{s.diagnostic_groups},\"scan_issues\":\{s.scan_issues}}," +
  "\"diagnostics\":[" +
  rendered.join(",") +
  "],\"limitations\":" +
  json_strings(report.limitations) +
  "}"
}

///|
/// Human-readable output quotes paths so control characters remain data.
pub fn render_text(report : Report) -> String {
  let status = if !report.complete {
    "INCOMPLETE"
  } else if report.diagnostics.is_empty() {
    "PASS (covered rules only)"
  } else {
    "FINDINGS"
  }
  let lines = [
    "MoonPortCheck — \{report.profile}",
    "\{status}; source=\{report.source}; entries=\{report.summary.entries}; files=\{report.summary.files}; directories=\{report.summary.directories}",
  ]
  let diagnostics = report.diagnostics.copy()
  sort_diagnostics(diagnostics)
  for d in diagnostics {
    let paths = d.paths.copy()
    paths.sort_by(ordinal_compare)
    lines.push(
      "[\{d.code}] " +
      paths.map(quote).join(", ") +
      " (occurrences=\{d.occurrences}): " +
      d.message,
    )
  }
  lines.push("Coverage limits:")
  for limitation in report.limitations {
    lines.push("- " + limitation)
  }
  lines.join("\n")
}

///|
fn quote(text : String) -> String {
  text.to_json().stringify()
}

///|
fn json_strings(items : Array[String]) -> String {
  "[" + items.map(quote).join(",") + "]"
}
