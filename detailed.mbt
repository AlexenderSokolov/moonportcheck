///|
/// Validated audit settings. Use default_audit_options to create v0.2 settings.
pub struct AuditOptions {
  priv sample_limit : Int
}

///|
pub fn default_audit_options() -> AuditOptions {
  { sample_limit: 5, }
}

///|
pub(all) struct SourceMember {
  path : String
  kind : EntryKind
  count : Int
} derive(Eq, Debug)

///|
pub(all) struct DetailedDiagnostic {
  code : String
  severity : String
  paths : Array[String]
  occurrences : Int
  message : String
  anchor : String
  group_key : String
  members : Array[SourceMember]
  source_examples : Array[SourceMember]
  source_total : Int
  sources_truncated : Bool
} derive(Eq, Debug)

///|
pub(all) struct ScanIssue {
  code : String
  path : String
  message : String
} derive(Eq, Debug)

///|
pub(all) struct DetailedReport {
  schema_version : Int
  profile : String
  source : String
  complete : Bool
  summary : Summary
  diagnostics : Array[DetailedDiagnostic]
  limitations : Array[String]
  scan_issues : Array[ScanIssue]
  scope : Array[String]
  excluded_entries : Int
  pruned_directories : Array[String]
} derive(Eq, Debug)

///|
pub extend SourceMember with Eq::{equal, not_equal}

///|
pub extend SourceMember with @debug.Debug::{to_repr}

///|
pub extend DetailedDiagnostic with Eq::{equal, not_equal}

///|
pub extend DetailedDiagnostic with @debug.Debug::{to_repr}

///|
pub extend ScanIssue with Eq::{equal, not_equal}

///|
pub extend ScanIssue with @debug.Debug::{to_repr}

///|
pub extend DetailedReport with Eq::{equal, not_equal}

///|
pub extend DetailedReport with @debug.Debug::{to_repr}

///|
priv struct SourceEvidence {
  item : SourceMember
  spelling : String
  file_role : Bool
  directory_role : Bool
}

///|
fn source_kind_name(kind : EntryKind) -> String {
  match kind {
    File => "file"
    Directory => "directory"
  }
}

///|
fn source_member_order(a : SourceMember, b : SourceMember) -> Int {
  let order = ordinal_compare(a.path, b.path)
  if order != 0 {
    return order
  }
  ordinal_compare(source_kind_name(a.kind), source_kind_name(b.kind))
}

///|
fn detailed_order(a : DetailedDiagnostic, b : DetailedDiagnostic) -> Int {
  let order = ordinal_compare(a.code, b.code)
  if order != 0 {
    return order
  }
  ordinal_compare(a.anchor, b.anchor)
}

///|
fn sort_scan_issues(issues : Array[ScanIssue]) -> Unit {
  issues.sort_by((a, b) => {
    let code = ordinal_compare(a.code, b.code)
    if code != 0 {
      return code
    }
    let path = ordinal_compare(a.path, b.path)
    if path != 0 {
      return path
    }
    ordinal_compare(a.message, b.message)
  })
}

///|
fn source_samples(
  code : String,
  evidence : Array[SourceEvidence],
  limit : Int,
) -> Array[SourceMember] {
  let selected : Array[Int] = []
  if code == "PATH_CASE_COLLISION" && !evidence.is_empty() {
    selected.push(0)
    for i in 1..<evidence.length() {
      if evidence[i].spelling != evidence[0].spelling {
        selected.push(i)
        break
      }
    }
  } else if code == "PATH_KIND_CONFLICT" {
    for i, source in evidence {
      if source.file_role {
        selected.push(i)
        break
      }
    }
    for i, source in evidence {
      if source.directory_role && !selected.contains(i) {
        selected.push(i)
        break
      }
    }
  }
  for i in 0..<evidence.length() {
    if selected.length() >= limit {
      break
    }
    if !selected.contains(i) {
      selected.push(i)
    }
  }
  // The two mandatory witnesses above fit the private default limit of five.
  let samples = selected.map(i => evidence[i].item)
  samples.sort_by(source_member_order)
  samples
}

///|
/// Preserve v1 diagnostic meaning and add original input evidence only where needed.
pub fn audit_with_options(
  entries : Array[PathEntry],
  options : AuditOptions,
) -> DetailedReport {
  let base = audit(entries)
  let counts : Map[String, PathCounts] = Map([])
  for entry in entries {
    let count = match counts.get(entry.path) {
      Some(count) => count
      None => {
        let count = { files: 0, directories: 0, }
        counts[entry.path] = count
        count
      }
    }
    match entry.kind {
      File => count.files += 1
      Directory => count.directories += 1
    }
  }
  let conflicts : Map[String, Array[SourceEvidence]] = Map([])
  let structurally_invalid : Map[String, Bool] = Map([])
  for diagnostic in base.diagnostics {
    match diagnostic.code {
      "PATH_CASE_COLLISION" | "PATH_KIND_CONFLICT" => {
        let anchor = ascii_lower(diagnostic.paths[0])
        if !conflicts.contains(anchor) {
          conflicts[anchor] = []
        }
      }
      "PATH_EMPTY"
      | "PATH_ABSOLUTE"
      | "PATH_DRIVE"
      | "PATH_EMPTY_COMPONENT"
      | "PATH_DOT_COMPONENT" => structurally_invalid[diagnostic.paths[0]] = true
      _ => ()
    }
  }
  let by_path : Map[String, Array[SourceMember]] = Map([])
  for path in sorted_keys(counts) {
    let count = counts[path]
    let members : Array[SourceMember] = []
    if count.directories > 0 {
      members.push({ path, kind: Directory, count: count.directories, })
    }
    if count.files > 0 {
      members.push({ path, kind: File, count: count.files, })
    }
    by_path[path] = members
    if conflicts.is_empty() || structurally_invalid.contains(path) {
      continue
    }
    let parts = path.split("/").map(p => p.to_owned()).collect()
    let mut prefix = ""
    for i, part in parts {
      prefix = if i == 0 { part } else { prefix + "/" + part }
      guard conflicts.get(ascii_lower(prefix)) is Some(sources) else {
        continue
      }
      for item in members {
        sources.push({
          item,
          spelling: prefix,
          file_role: i == parts.length() - 1 && item.kind == File,
          directory_role: i < parts.length() - 1 || item.kind == Directory,
        })
      }
    }
  }
  let diagnostics = base.diagnostics.map(d => {
    let grouped = d.code == "PATH_CASE_COLLISION" ||
      d.code == "PATH_KIND_CONFLICT"
    let anchor = if grouped { ascii_lower(d.paths[0]) } else { d.paths[0] }
    let evidence = if grouped {
      conflicts[anchor]
    } else {
      by_path[anchor].map(item => {
        item,
        spelling: anchor,
        file_role: item.kind == File,
        directory_role: item.kind == Directory,
      })
    }
    let members = evidence.map(source => source.item)
    let source_examples = source_samples(d.code, evidence, options.sample_limit)
    {
      code: d.code,
      severity: d.severity,
      paths: d.paths,
      occurrences: d.occurrences,
      message: d.message,
      anchor,
      group_key: json_strings([d.code, anchor]),
      members,
      source_examples,
      source_total: members.length(),
      sources_truncated: members.length() > source_examples.length(),
    }
  })
  diagnostics.sort_by(detailed_order)
  {
    schema_version: 2,
    profile: base.profile,
    source: base.source,
    complete: base.complete,
    summary: base.summary,
    diagnostics,
    limitations: base.limitations,
    scan_issues: [],
    scope: [],
    excluded_entries: 0,
    pruned_directories: [],
  }
}

///|
/// Add scan issues without inventing file/directory evidence or losing prior issues.
pub fn with_scan_issues(
  report : DetailedReport,
  issues : Array[ScanIssue],
) -> DetailedReport {
  let combined = report.scan_issues.copy()
  for issue in issues {
    combined.push(issue)
  }
  sort_scan_issues(combined)
  {
    schema_version: report.schema_version,
    profile: report.profile,
    source: "scan",
    complete: report.complete && combined.is_empty(),
    summary: {
      entries: report.summary.entries,
      files: report.summary.files,
      directories: report.summary.directories,
      diagnostic_groups: report.diagnostics.length(),
      scan_issues: combined.length(),
    },
    diagnostics: report.diagnostics,
    limitations: report.limitations,
    scan_issues: combined,
    scope: report.scope,
    excluded_entries: report.excluded_entries,
    pruned_directories: report.pruned_directories,
  }
}

///|
fn render_source_members(members : Array[SourceMember]) -> String {
  let sorted = members.copy()
  sorted.sort_by(source_member_order)
  "[" +
  sorted
  .map(item => {
    "{\"path\":" +
    quote(item.path) +
    ",\"kind\":" +
    quote(source_kind_name(item.kind)) +
    ",\"count\":\{item.count}}"
  })
  .join(",") +
  "]"
}

///|
/// Deterministic schema 2 serialization; v1 render_json remains unchanged.
pub fn render_detailed_json(report : DetailedReport) -> String {
  let diagnostics = report.diagnostics.copy()
  diagnostics.sort_by(detailed_order)
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
    ",\"anchor\":" +
    quote(d.anchor) +
    ",\"group_key\":" +
    quote(d.group_key) +
    ",\"members\":" +
    render_source_members(d.members) +
    ",\"source_examples\":" +
    render_source_members(d.source_examples) +
    ",\"source_total\":\{d.source_total},\"sources_truncated\":\{d.sources_truncated}}"
  })
  let issues = report.scan_issues.copy()
  sort_scan_issues(issues)
  let rendered_issues = issues.map(issue => {
    "{\"code\":" +
    quote(issue.code) +
    ",\"path\":" +
    quote(issue.path) +
    ",\"message\":" +
    quote(issue.message) +
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
  ",\"scan_issues\":[" +
  rendered_issues.join(",") +
  "],\"scope\":" +
  json_strings(report.scope) +
  ",\"excluded_entries\":\{report.excluded_entries},\"pruned_directories\":" +
  json_strings(report.pruned_directories) +
  "}"
}

///|
/// Human-readable schema 2 findings with bounded original-entry witnesses.
pub fn render_detailed_text(report : DetailedReport) -> String {
  let status = if !report.complete {
    "INCOMPLETE"
  } else if report.diagnostics.is_empty() {
    "PASS (covered rules only)"
  } else {
    "FINDINGS"
  }
  let lines = [
    "MoonPortCheck — \{report.profile}; schema=\{report.schema_version}",
    "\{status}; source=\{report.source}; entries=\{report.summary.entries}; files=\{report.summary.files}; directories=\{report.summary.directories}",
    "Scope exclusions: " +
    json_strings(report.scope) +
    "; excluded_entries=\{report.excluded_entries}; pruned_directories=" +
    json_strings(report.pruned_directories),
  ]
  let diagnostics = report.diagnostics.copy()
  diagnostics.sort_by(detailed_order)
  for d in diagnostics {
    let paths = d.paths.copy()
    paths.sort_by(ordinal_compare)
    lines.push(
      "[\{d.code}] " +
      paths.map(quote).join(", ") +
      " (occurrences=\{d.occurrences}): " +
      d.message,
    )
    lines.push("  Group: " + d.group_key)
    lines.push(
      "  Source samples: \{d.source_examples.length()}/\{d.source_total}; truncated=\{d.sources_truncated}",
    )
    let samples = d.source_examples.copy()
    samples.sort_by(source_member_order)
    for item in samples {
      lines.push(
        "  - " +
        quote(item.path) +
        " (kind=" +
        source_kind_name(item.kind) +
        "; count=\{item.count})",
      )
    }
  }
  let issues = report.scan_issues.copy()
  sort_scan_issues(issues)
  for issue in issues {
    lines.push(
      "[\{issue.code}] " + quote(issue.path) + ": " + quote(issue.message),
    )
  }
  lines.push("Coverage limits:")
  for limitation in report.limitations {
    lines.push("- " + limitation)
  }
  lines.join("\n")
}

///|
/// Markdown rendering of a schema 2 report. The status, scopes, diagnostics
/// and scan issues mirror `render_detailed_text` so every format reaches the
/// same conclusion; paths are escaped so a hostile name cannot break a table.
pub fn render_detailed_markdown(report : DetailedReport) -> String {
  let status = if !report.complete {
    "INCOMPLETE"
  } else if report.diagnostics.is_empty() {
    "PASS (covered rules only)"
  } else {
    "FINDINGS"
  }
  let lines = [
    "# MoonPortCheck report",
    "",
    "**Status:** `" +
    status +
    "` · **Profile:** `" +
    report.profile +
    "` · **Source:** `" +
    report.source +
    "` · **Entries:** " +
    report.summary.entries.to_string() +
    " (files " +
    report.summary.files.to_string() +
    ", directories " +
    report.summary.directories.to_string() +
    ")",
    "",
    "**Scope exclusions:** `" +
    json_strings(report.scope) +
    "`; excluded_entries=" +
    report.excluded_entries.to_string() +
    "; pruned_directories=`" +
    json_strings(report.pruned_directories) +
    "`",
    "",
  ]
  lines.push("## Findings")
  lines.push("")
  let diagnostics = report.diagnostics.copy()
  diagnostics.sort_by(detailed_order)
  if diagnostics.is_empty() {
    lines.push("No findings.")
  } else {
    lines.push("| Code | Paths | Occurrences | Message |")
    lines.push("| --- | --- | --- | --- |")
    for d in diagnostics {
      let paths = d.paths.copy()
      paths.sort_by(ordinal_compare)
      lines.push(
        "| `" +
        md_cell(d.code) +
        "` | " +
        paths.map(path => "`" + md_cell(path) + "`").join(", ") +
        " | " +
        d.occurrences.to_string() +
        " | " +
        md_cell(d.message) +
        " |",
      )
    }
  }
  lines.push("")
  lines.push("## Scan issues")
  lines.push("")
  let issues = report.scan_issues.copy()
  sort_scan_issues(issues)
  if issues.is_empty() {
    lines.push("No scan issues.")
  } else {
    lines.push("| Code | Path | Message |")
    lines.push("| --- | --- | --- |")
    for issue in issues {
      lines.push(
        "| `" +
        md_cell(issue.code) +
        "` | `" +
        md_cell(issue.path) +
        "` | " +
        md_cell(issue.message) +
        " |",
      )
    }
  }
  lines.push("")
  lines.push("## Coverage limits")
  if report.limitations.is_empty() {
    lines.push("None.")
  } else {
    for limitation in report.limitations {
      lines.push("- " + md_cell(limitation))
    }
  }
  lines.join("\n")
}

///|
fn parse_int_field(
  fields : Map[String, Json],
  name : String,
) -> Result[Int, InputError] {
  match fields.get(name) {
    Some(Number(n, ..)) => {
      let int = n.to_int()
      if int.to_double() == n {
        Ok(int)
      } else {
        Err({
          code: "INPUT_SCHEMA",
          message: "The " + name + " field must be an integer.",
        })
      }
    }
    _ =>
      Err({
        code: "INPUT_SCHEMA",
        message: "The " + name + " field requires an integer.",
      })
  }
}

///|
fn reject_unknown_fields(
  fields : Map[String, Json],
  allowed : Array[String],
) -> Result[Unit, InputError] {
  for name in fields.keys() {
    if !allowed.contains(name) {
      return Err({ code: "INPUT_SCHEMA", message: "Unknown field: " + name, })
    }
  }
  Ok(())
}

///|
fn parse_diagnostic_strings(
  items : Array[Json],
  label : String,
) -> Result[Array[String], InputError] {
  let strings : Array[String] = []
  for index in 0..<items.length() {
    guard items[index] is String(value) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "The " + label + " array requires strings.",
      })
    }
    strings.push(value)
  }
  Ok(strings)
}

///|
fn parse_source_members(
  items : Array[Json],
) -> Result[Array[SourceMember], InputError] {
  let members : Array[SourceMember] = []
  for index in 0..<items.length() {
    guard items[index] is Object(fields) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "A source member must be an object.",
      })
    }
    match reject_unknown_fields(fields, ["path", "kind", "count"]) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    guard fields.get("path") is Some(String(path)) else {
      return Err({
        code: "INPUT_SCHEMA",
        message: "A source member requires a path.",
      })
    }
    let kind = match fields.get("kind") {
      Some(String("file")) => File
      Some(String("directory")) => Directory
      _ =>
        return Err({
          code: "INPUT_SCHEMA",
          message: "A source member kind must be file or directory.",
        })
    }
    let count = match parse_int_field(fields, "count") {
      Err(error) => return Err(error)
      Ok(count) => count
    }
    members.push({ path, kind, count, })
  }
  Ok(members)
}

///|
fn parse_detailed_diagnostic(
  fields : Map[String, Json],
) -> Result[DetailedDiagnostic, InputError] {
  match
    reject_unknown_fields(fields, [
      "code", "severity", "paths", "occurrences", "message", "anchor", "group_key",
      "members", "source_examples", "source_total", "sources_truncated",
    ]) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard fields.get("code") is Some(String(code)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "A diagnostic requires a code.",
    })
  }
  guard fields.get("severity") is Some(String(severity)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "A diagnostic requires a severity.",
    })
  }
  let paths = match fields.get("paths") {
    Some(Array(items)) =>
      match parse_diagnostic_strings(items, "paths") {
        Err(error) => return Err(error)
        Ok(values) => values
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "A diagnostic requires a paths array.",
      })
  }
  let occurrences = match parse_int_field(fields, "occurrences") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  guard fields.get("message") is Some(String(message)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "A diagnostic requires a message.",
    })
  }
  guard fields.get("anchor") is Some(String(anchor)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "A diagnostic requires an anchor.",
    })
  }
  guard fields.get("group_key") is Some(String(group_key)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "A diagnostic requires a group_key.",
    })
  }
  let members = match fields.get("members") {
    Some(Array(items)) =>
      match parse_source_members(items) {
        Err(error) => return Err(error)
        Ok(values) => values
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "A diagnostic requires a members array.",
      })
  }
  let source_examples = match fields.get("source_examples") {
    Some(Array(items)) =>
      match parse_source_members(items) {
        Err(error) => return Err(error)
        Ok(values) => values
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "A diagnostic requires a source_examples array.",
      })
  }
  let source_total = match parse_int_field(fields, "source_total") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let sources_truncated = match fields.get("sources_truncated") {
    Some(True) => true
    Some(False) => false
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "A diagnostic requires a boolean sources_truncated.",
      })
  }
  Ok({
    code,
    severity,
    paths,
    occurrences,
    message,
    anchor,
    group_key,
    members,
    source_examples,
    source_total,
    sources_truncated,
  })
}

///|
/// Parse a schema 2 report document produced by render_detailed_json. The
/// parser is strict about field names and rejects unknown members so a
/// baseline cannot silently drop a newly added report field.
pub fn parse_detailed_report(
  text : String,
) -> Result[DetailedReport, InputError] {
  let value = @json.parse(text) catch {
    _ =>
      return Err({ code: "INPUT_JSON", message: "Invalid JSON in the report.", })
  }
  guard value is Object(fields) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The report must be a JSON object.",
    })
  }
  match
    reject_unknown_fields(fields, [
      "schema_version", "profile", "source", "complete", "summary", "diagnostics",
      "limitations", "scan_issues", "scope", "excluded_entries", "pruned_directories",
      "baseline",
    ]) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match fields.get("schema_version") {
    Some(Number(n, ..)) if n == 2.0 => ()
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "Unsupported report schema version.",
      })
  }
  guard fields.get("profile") is Some(String(profile)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The report requires a string profile.",
    })
  }
  guard fields.get("source") is Some(String(source)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The report requires a source.",
    })
  }
  let complete = match fields.get("complete") {
    Some(True) => true
    Some(False) => false
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The report requires a boolean complete.",
      })
  }
  let summary = match fields.get("summary") {
    Some(Object(summary_fields)) => {
      match
        reject_unknown_fields(summary_fields, [
          "entries", "files", "directories", "diagnostic_groups", "scan_issues",
        ]) {
        Err(error) => return Err(error)
        Ok(_) => ()
      }
      let entries = match parse_int_field(summary_fields, "entries") {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let files = match parse_int_field(summary_fields, "files") {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let directories = match parse_int_field(summary_fields, "directories") {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let diagnostic_groups = match
        parse_int_field(summary_fields, "diagnostic_groups") {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      let scan_issues_summary = match
        parse_int_field(summary_fields, "scan_issues") {
        Err(error) => return Err(error)
        Ok(value) => value
      }
      {
        entries,
        files,
        directories,
        diagnostic_groups,
        scan_issues: scan_issues_summary,
      }
    }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The report requires a summary object.",
      })
  }
  let diagnostics = match fields.get("diagnostics") {
    Some(Array(items)) => {
      let list : Array[DetailedDiagnostic] = []
      for index in 0..<items.length() {
        guard items[index] is Object(item_fields) else {
          return Err({
            code: "INPUT_SCHEMA",
            message: "A diagnostic must be an object.",
          })
        }
        match parse_detailed_diagnostic(item_fields) {
          Err(error) => return Err(error)
          Ok(diagnostic) => list.push(diagnostic)
        }
      }
      list
    }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The report requires a diagnostics array.",
      })
  }
  let limitations = match fields.get("limitations") {
    Some(Array(items)) =>
      match parse_diagnostic_strings(items, "limitations") {
        Err(error) => return Err(error)
        Ok(values) => values
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The report requires a limitations array.",
      })
  }
  let scan_issues = match fields.get("scan_issues") {
    Some(Array(items)) => {
      for item in items {
        if item is Object(issue_fields) {
          match
            reject_unknown_fields(issue_fields, ["code", "path", "message"]) {
            Err(error) => return Err(error)
            Ok(_) => ()
          }
        }
      }
      match parse_snapshot_issues(items) {
        Err(error) => return Err(error)
        Ok(values) => values
      }
    }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The report requires a scan_issues array.",
      })
  }
  let scope = match fields.get("scope") {
    Some(Array(items)) =>
      match collect_snapshot_strings(items, "scope") {
        Err(error) => return Err(error)
        Ok(values) => values
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The report requires a scope array.",
      })
  }
  let excluded_entries = match parse_int_field(fields, "excluded_entries") {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let pruned_directories = match fields.get("pruned_directories") {
    Some(Array(items)) =>
      match parse_diagnostic_strings(items, "pruned_directories") {
        Err(error) => return Err(error)
        Ok(values) => values
      }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The report requires a pruned_directories array.",
      })
  }
  Ok({
    schema_version: 2,
    profile,
    source,
    complete,
    summary,
    diagnostics,
    limitations,
    scan_issues,
    scope,
    excluded_entries,
    pruned_directories,
  })
}
