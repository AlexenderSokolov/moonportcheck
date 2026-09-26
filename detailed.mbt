///|
/// Validated audit settings. Use default_audit_options to create v0.2 settings.
pub struct AuditOptions {
  sample_limit : Int
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
