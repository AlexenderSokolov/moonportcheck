///|
/// Classification of a diagnostic group relative to a historical baseline.
pub enum BaselineStatus {
  New
  Existing
  Worsened
  Resolved
} derive(Eq, Debug)

///|
pub extend BaselineStatus with Eq::{equal, not_equal}

///|
pub extend BaselineStatus with @debug.Debug::{to_repr}

///|
/// An immutable group in a baseline document, identified by rule code and the
/// stable path anchor. members is the full member list with per-member counts.
pub struct BaselineGroup {
  code : String
  anchor : String
  members : Array[SourceMember]
  source_total : Int
} derive(Eq, Debug)

///|
pub extend BaselineGroup with Eq::{equal, not_equal}

///|
pub extend BaselineGroup with @debug.Debug::{to_repr}

///|
/// The baseline document: created only from a complete schema 2 audit report,
/// binding the profile, rule version and effective scan scope to its groups.
pub struct Baseline {
  format : String
  schema_version : Int
  profile : String
  rules_version : String
  scope : Array[String]
  groups : Array[BaselineGroup]
} derive(Eq, Debug)

///|
pub extend Baseline with Eq::{equal, not_equal}

///|
pub extend Baseline with @debug.Debug::{to_repr}

///|
/// One classified group after comparing a report against a baseline. members and
/// source_total describe the current report state; a resolved group is empty.
pub struct BaselineChange {
  code : String
  anchor : String
  status : BaselineStatus
  members : Array[SourceMember]
  source_total : Int
} derive(Eq, Debug)

///|
pub extend BaselineChange with Eq::{equal, not_equal}

///|
pub extend BaselineChange with @debug.Debug::{to_repr}

///|
pub struct BaselineDiff {
  changes : Array[BaselineChange]
} derive(Eq, Debug)

///|
pub extend BaselineDiff with Eq::{equal, not_equal}

///|
pub extend BaselineDiff with @debug.Debug::{to_repr}

///|
fn baseline_status_name(status : BaselineStatus) -> String {
  match status {
    New => "new"
    Existing => "existing"
    Worsened => "worsened"
    Resolved => "resolved"
  }
}

///|
fn baseline_status_rank(status : BaselineStatus) -> Int {
  match status {
    New => 0
    Worsened => 1
    Existing => 2
    Resolved => 3
  }
}

///|
fn baseline_group_order(a : BaselineGroup, b : BaselineGroup) -> Int {
  let code = ordinal_compare(a.code, b.code)
  if code != 0 {
    return code
  }
  ordinal_compare(a.anchor, b.anchor)
}

///|
fn baseline_change_order(a : BaselineChange, b : BaselineChange) -> Int {
  let rank_a = baseline_status_rank(a.status)
  let rank_b = baseline_status_rank(b.status)
  let rank = if rank_a == rank_b { 0 } else if rank_a < rank_b { -1 } else { 1 }
  if rank != 0 {
    return rank
  }
  let code = ordinal_compare(a.code, b.code)
  if code != 0 {
    return code
  }
  ordinal_compare(a.anchor, b.anchor)
}

///|
/// Return the absolute rule-version string for the current catalog. A baseline
/// records this value so a later report from different rules can be rejected.
pub fn rules_version() -> String {
  "1"
}

///|
/// Build a baseline from a complete schema 2 audit report. Incomplete reports
/// and non-schema-2 documents are rejected with structured input errors.
pub fn build_baseline(report : DetailedReport) -> Result[Baseline, InputError] {
  if report.schema_version != 2 {
    return Err({
      code: "INPUT_SCHEMA",
      message: "A baseline requires a schema 2 report.",
    })
  }
  if report.complete == false || report.scan_issues.is_empty() == false {
    return Err({
      code: "INPUT_INCOMPLETE",
      message: "A baseline requires a complete report without scan issues.",
    })
  }
  let groups = report.diagnostics.map(d => {
    let members = d.members.copy()
    members.sort_by(source_member_order)
    { code: d.code, anchor: d.anchor, members, source_total: d.source_total, }
  })
  groups.sort_by(baseline_group_order)
  Ok({
    format: "moonportcheck-baseline",
    schema_version: 1,
    profile: report.profile,
    rules_version: rules_version(),
    scope: report.scope.copy(),
    groups,
  })
}

///|
fn member_key(item : SourceMember) -> String {
  item.path + "\u0000" + source_kind_name(item.kind)
}

///|
fn member_map(members : Array[SourceMember]) -> Map[String, Int] {
  let map : Map[String, Int] = Map([])
  for item in members {
    let key = member_key(item)
    let previous = match map.get(key) {
      None => 0
      Some(count) => count
    }
    map[key] = previous + item.count
  }
  map
}

///|
/// A matched group worsens when a member count rises or a brand-new member
/// path/kind appears. Losing members alone keeps the group existing.
fn group_worsened(before : Map[String, Int], after : Map[String, Int]) -> Bool {
  let keys = after.keys().collect()
  keys.sort_by(ordinal_compare)
  for key in keys {
    let previous = match before.get(key) {
      None => 0
      Some(count) => count
    }
    if after[key] > previous {
      return true
    }
  }
  false
}

///|
/// Classify every diagnostic group of a report against a historical baseline.
/// Groups are associated by rule code plus stable path anchor; members and
/// their counts are compared as multisets. Returns a stable diff document.
pub fn diff_with_baseline(
  baseline : Baseline,
  report : DetailedReport,
) -> BaselineDiff {
  let report_by_key : Map[String, DetailedDiagnostic] = Map([])
  for diagnostic in report.diagnostics {
    report_by_key[diagnostic.code + "\u0000" + diagnostic.anchor] = diagnostic
  }
  let baseline_by_key : Map[String, BaselineGroup] = Map([])
  for group in baseline.groups {
    baseline_by_key[group.code + "\u0000" + group.anchor] = group
  }
  let changes : Array[BaselineChange] = []
  for group in baseline.groups {
    let key = group.code + "\u0000" + group.anchor
    let status : BaselineStatus = match report_by_key.get(key) {
      None => Resolved
      Some(current) => {
        let before = member_map(group.members)
        let after = member_map(current.members)
        if group_worsened(before, after) {
          Worsened
        } else {
          Existing
        }
      }
    }
    let (members, source_total) = match report_by_key.get(key) {
      None => {
        let empty : Array[SourceMember] = []
        (empty, 0)
      }
      Some(current) => {
        let sorted = current.members.copy()
        sorted.sort_by(source_member_order)
        (sorted, current.source_total)
      }
    }
    changes.push({
      code: group.code,
      anchor: group.anchor,
      status,
      members,
      source_total,
    })
  }
  for diagnostic in report.diagnostics {
    if baseline_by_key.contains(diagnostic.code + "\u0000" + diagnostic.anchor) {
      continue
    }
    let sorted = diagnostic.members.copy()
    sorted.sort_by(source_member_order)
    changes.push({
      code: diagnostic.code,
      anchor: diagnostic.anchor,
      status: New,
      members: sorted,
      source_total: diagnostic.source_total,
    })
  }
  changes.sort_by(baseline_change_order)
  { changes, }
}

///|
/// Stable serialization of a baseline document with fixed field order.
pub fn render_baseline_json(baseline : Baseline) -> String {
  "{\"format\":" +
  quote(baseline.format) +
  ",\"schema_version\":\{baseline.schema_version},\"profile\":" +
  quote(baseline.profile) +
  ",\"rules_version\":" +
  quote(baseline.rules_version) +
  ",\"scope\":" +
  json_strings(baseline.scope) +
  ",\"groups\":[" +
  baseline.groups
  .map(group => {
    "{\"code\":" +
    quote(group.code) +
    ",\"anchor\":" +
    quote(group.anchor) +
    ",\"members\":" +
    render_source_members(group.members) +
    ",\"source_total\":\{group.source_total}}"
  })
  .join(",") +
  "]}"
}

///|
/// Stable serialization of a classification document with fixed field order.
pub fn render_baseline_diff_json(diff : BaselineDiff) -> String {
  "{\"format\":\"moonportcheck-baseline-diff\",\"schema_version\":1,\"changes\":[" +
  diff.changes
  .map(change => {
    "{\"code\":" +
    quote(change.code) +
    ",\"anchor\":" +
    quote(change.anchor) +
    ",\"status\":" +
    quote(baseline_status_name(change.status)) +
    ",\"members\":" +
    render_source_members(change.members) +
    ",\"source_total\":\{change.source_total}}"
  })
  .join(",") +
  "]}"
}

///|
/// Stable human-readable classification for text output.
pub fn render_baseline_diff_text(diff : BaselineDiff) -> String {
  if diff.changes.is_empty() {
    return "No baseline changes.\n"
  }
  let lines = diff.changes.map(change => {
    "[" +
    baseline_status_name(change.status) +
    "] " +
    change.code +
    "@" +
    change.anchor +
    " (current_source_total=\{change.source_total})"
  })
  lines.join("\n") + "\n"
}

///|
/// Parse a baseline document produced by render_baseline_json. Field names are
/// strict so a baseline cannot silently drop a newly added future field.
pub fn parse_baseline(text : String) -> Result[Baseline, InputError] {
  let value = @json.parse(text) catch {
    _ =>
      return Err({
        code: "INPUT_JSON",
        message: "Invalid JSON in the baseline.",
      })
  }
  guard value is Object(fields) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The baseline must be a JSON object.",
    })
  }
  match fields.get("format") {
    Some(String("moonportcheck-baseline")) => ()
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "Unsupported baseline format.",
      })
  }
  match fields.get("schema_version") {
    Some(Number(n, ..)) if n == 1.0 => ()
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "Unsupported baseline version.",
      })
  }
  guard fields.get("profile") is Some(String(profile)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The baseline requires a profile.",
    })
  }
  guard fields.get("rules_version") is Some(String(rules_version)) else {
    return Err({
      code: "INPUT_SCHEMA",
      message: "The baseline requires a rules_version.",
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
        message: "The baseline requires a scope array.",
      })
  }
  let normalized_scope = match parse_scope(scope) {
    Err(error) => return Err(error)
    Ok(parsed) => effective_scope_patterns(parsed)
  }
  let groups = match fields.get("groups") {
    Some(Array(items)) => {
      let list : Array[BaselineGroup] = []
      for index in 0..<items.length() {
        guard items[index] is Object(group_fields) else {
          return Err({
            code: "INPUT_SCHEMA",
            message: "A baseline group must be an object.",
          })
        }
        match
          reject_unknown_fields(group_fields, [
            "code", "anchor", "members", "source_total",
          ]) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
        guard group_fields.get("code") is Some(String(code)) else {
          return Err({
            code: "INPUT_SCHEMA",
            message: "A baseline group requires a code.",
          })
        }
        guard group_fields.get("anchor") is Some(String(anchor)) else {
          return Err({
            code: "INPUT_SCHEMA",
            message: "A baseline group requires an anchor.",
          })
        }
        let members = match group_fields.get("members") {
          Some(Array(items)) =>
            match parse_source_members(items) {
              Err(error) => return Err(error)
              Ok(values) => values
            }
          _ =>
            return Err({
              code: "INPUT_SCHEMA",
              message: "A baseline group requires a members array.",
            })
        }
        let source_total = match parse_int_field(group_fields, "source_total") {
          Err(error) => return Err(error)
          Ok(value) => value
        }
        list.push({ code, anchor, members, source_total, })
      }
      list
    }
    _ =>
      return Err({
        code: "INPUT_SCHEMA",
        message: "The baseline requires a groups array.",
      })
  }
  for name in fields.keys() {
    match name {
      "format"
      | "schema_version"
      | "profile"
      | "rules_version"
      | "scope"
      | "groups" => ()
      _ =>
        return Err({
          code: "INPUT_SCHEMA",
          message: "Unknown baseline field: " + name,
        })
    }
  }
  Ok({
    format: "moonportcheck-baseline",
    schema_version: 1,
    profile,
    rules_version,
    scope: normalized_scope,
    groups,
  })
}
