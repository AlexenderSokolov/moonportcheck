///|
/// A validated, deduplicated exclusion scope. Build with parse_scope.
pub struct ExclusionScope {
  priv patterns : Array[String]
  priv compiled : Array[PathPattern]
}

///|
/// Validate every pattern; the whole scope fails on the first invalid one.
/// Patterns are deduplicated by exact spelling and kept in ordinal order so the
/// delivered report is independent of config and command-line ordering.
pub fn parse_scope(
  patterns : Array[String],
) -> Result[ExclusionScope, InputError] {
  let unique : Map[String, Bool] = Map([])
  for pattern in patterns {
    unique[pattern] = true
  }
  let keys = sorted_keys(unique)
  let compiled : Array[PathPattern] = []
  for pattern in keys {
    match parse_pattern(pattern) {
      Err(error) => return Err(error)
      Ok(compiled_pattern) => compiled.push(compiled_pattern)
    }
  }
  Ok({ patterns: keys, compiled, })
}

///|
/// The normalized scope recorded in reports: unique patterns in ordinal order.
pub fn effective_scope_patterns(scope : ExclusionScope) -> Array[String] {
  scope.patterns.copy()
}

///|
/// True when any pattern matches the entry. Structurally invalid paths never
/// match (pattern_matches guards on path structure), so they stay in scope.
pub fn entry_excluded(scope : ExclusionScope, entry : PathEntry) -> Bool {
  for pattern in scope.compiled {
    if pattern_matches(pattern, entry) {
      return true
    }
  }
  false
}

///|
/// Explicit directories plus the implicit directories implied by every entry
/// prefix become directories in this delivery tree.
fn directory_set(entries : Array[PathEntry]) -> Map[String, Bool] {
  let directories : Map[String, Bool] = Map([])
  for entry in entries {
    guard check_path(entry.path, 1, []) is Some(parts) else { continue }
    if entry.kind == Directory {
      directories[entry.path] = true
    }
    let mut prefix = ""
    for i in 0..<(parts.length() - 1) {
      prefix = if i == 0 { parts[0] } else { prefix + "/" + parts[i] }
      directories[prefix] = true
    }
  }
  directories
}

///|
/// Directories whose whole subtree is excluded, in ordinal order. Only the
/// top-most excluded directory of each path is reported: a real scan prunes at
/// the first matching ancestor and never visits deeper directories, so a check
/// over the equivalent manifest must agree by reporting the same minimal set.
/// Computed over the full (pre-filter) input so an excluded subtree's own
/// implicit directory is still represented. Descendant counts are never
/// extrapolated.
fn pruned_directories(
  scope : ExclusionScope,
  entries : Array[PathEntry],
) -> Array[String] {
  let directories = directory_set(entries)
  let matching : Map[String, Bool] = Map([])
  for directory in sorted_keys(directories) {
    if entry_excluded(scope, { path: directory, kind: Directory, }) {
      matching[directory] = true
    }
  }
  let pruned : Array[String] = []
  for directory in sorted_keys(matching) {
    if !has_pruned_ancestor(directory, matching) {
      pruned.push(directory)
    }
  }
  pruned
}

///|
/// Whether a proper ancestor of this directory is itself fully excluded.
fn has_pruned_ancestor(path : String, matching : Map[String, Bool]) -> Bool {
  guard check_path(path, 1, []) is Some(parts) else { return false }
  if parts.length() <= 1 {
    return false
  }
  let mut prefix = parts[0]
  for i in 1..<parts.length() {
    if matching.contains(prefix) {
      return true
    }
    prefix = prefix + "/" + parts[i]
  }
  false
}

///|
/// Filter input by the scope first, then audit the retained entries. Excluded
/// entries leave the summary and diagnostics but are counted, and the scope,
/// known excluded count and actually pruned directories are recorded.
pub fn audit_with_exclusions(
  entries : Array[PathEntry],
  options : AuditOptions,
  scope : ExclusionScope,
) -> DetailedReport {
  let retained : Array[PathEntry] = []
  let mut excluded = 0
  for entry in entries {
    if entry_excluded(scope, entry) {
      excluded += 1
    } else {
      retained.push(entry)
    }
  }
  let base = audit_with_options(retained, options)
  {
    schema_version: base.schema_version,
    profile: base.profile,
    source: base.source,
    complete: base.complete,
    summary: base.summary,
    diagnostics: base.diagnostics,
    limitations: base.limitations,
    scan_issues: base.scan_issues,
    scope: scope.patterns.copy(),
    excluded_entries: excluded,
    pruned_directories: pruned_directories(scope, entries),
  }
}
