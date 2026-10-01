///|
fn parsed_scope(
  patterns : Array[String],
) -> @moonportcheck.ExclusionScope raise {
  match @moonportcheck.parse_scope(patterns) {
    Ok(scope) => scope
    Err(error) => fail("Valid scope rejected: " + error.message)
  }
}

///|
fn audit_report(
  entries : Array[@moonportcheck.PathEntry],
  patterns : Array[String],
) -> @moonportcheck.DetailedReport raise {
  @moonportcheck.audit_with_exclusions(
    entries,
    @moonportcheck.default_audit_options(),
    parsed_scope(patterns),
  )
}

///|
fn file(path : String) -> @moonportcheck.PathEntry {
  { path, kind: @moonportcheck.File, }
}

///|
fn directory(path : String) -> @moonportcheck.PathEntry {
  { path, kind: @moonportcheck.Directory, }
}

///|
test "parse_scope deduplicates and orders patterns" {
  let scope = parsed_scope(["cache", "*.tmp", "cache", "cache/"])
  assert_eq(@moonportcheck.effective_scope_patterns(scope), [
    "*.tmp", "cache", "cache/",
  ])
  assert_true(
    @moonportcheck.effective_scope_patterns(parsed_scope([])).is_empty(),
  )
}

///|
test "parse_scope rejects invalid patterns with PATTERN_INVALID" {
  for text in ["", "a\\b", "a//b", "!a", "a[b]", "/abs", "C:x", "a**b"] {
    guard @moonportcheck.parse_scope([text]) is Err(error) else {
      fail("Invalid pattern accepted in scope: " + text)
    }
    assert_eq(error.code, "PATTERN_INVALID")
  }
}

///|
test "exclusion filters files and keeps retained counts" {
  let report = audit_report(
    [file("README.md"), file("notes/a.tmp"), file("notes/b.txt")],
    ["**/*.tmp"],
  )
  assert_eq(report.excluded_entries, 1)
  assert_eq(report.summary.entries, 2)
  assert_eq(report.summary.files, 2)
  assert_true(report.diagnostics.is_empty())
  assert_eq(report.scope, ["**/*.tmp"])
  assert_eq(report.pruned_directories, [])
}

///|
test "a root-only star glob does not reach nested files" {
  let report = audit_report([file("a.tmp"), file("notes/a.tmp")], ["*.tmp"])
  assert_eq(report.excluded_entries, 1) // only the root-level a.tmp
  assert_eq(report.summary.entries, 1)
}

///|
test "excluded directory and implicit prefixes are reported as pruned" {
  let report = audit_report(
    [directory("cache"), file("cache/x.tmp"), file("other/a.txt")],
    ["cache/"],
  )
  // cache and cache/x.tmp are excluded; other/a.txt is retained.
  assert_eq(report.excluded_entries, 2)
  assert_eq(report.summary.entries, 1)
  assert_eq(report.pruned_directories, ["cache"])
}

///|
test "implicit directory exclusion uses the same pruning semantics" {
  let report = audit_report([file("cache/x.tmp"), file("cache/y.txt")], [
    "cache",
  ])
  assert_eq(report.excluded_entries, 2)
  assert_eq(report.pruned_directories, ["cache"])
  let report2 = audit_report([file("cache/x.tmp"), file("cache/y.txt")], [
    "cache/",
  ])
  assert_eq(report2.excluded_entries, 2)
  assert_eq(report2.pruned_directories, ["cache"])
}

///|
test "cache without trailing slash also matches a root file; trailing slash does not" {
  let file_report = audit_report([file("cache")], ["cache"])
  assert_eq(file_report.excluded_entries, 1)
  let file_report2 = audit_report([file("cache")], ["cache/"])
  assert_eq(file_report2.excluded_entries, 0)
  let both = audit_report(
    [file("cache"), directory("cache-data"), file("cache-data/a.txt")],
    ["cache/"],
  )
  // cache (file) stays; cache-data and its descendant stay (name differs).
  assert_eq(both.excluded_entries, 0)
}

///|
test "whole recursive patterns apply to files but trailing slash only to directories" {
  let all = audit_report([file("a/b.txt"), file("c.txt"), directory("empty")], [
    "**",
  ])
  assert_eq(all.excluded_entries, 3)
  assert_eq(all.pruned_directories, ["a", "empty"])
  let dirs_only = audit_report(
    [file("a/b.txt"), file("c.txt"), directory("empty")],
    ["**/"],
  )
  // a/b.txt and empty are excluded; the root-level file c.txt is not.
  assert_eq(dirs_only.excluded_entries, 2)
  assert_eq(dirs_only.pruned_directories, ["a", "empty"])
}

///|
test "pruning never hides structurally invalid paths" {
  let report = audit_report(
    [file("/abs"), file("CON.txt"), file("../escape")],
    ["**"],
  )
  assert_eq(report.excluded_entries, 1) // only CON.txt has a valid structure
  assert_eq(report.summary.entries, 2) // the two structural paths remain
  let codes = report.diagnostics.map(d => d.code)
  assert_true(codes.contains("PATH_ABSOLUTE"))
  assert_true(codes.contains("PATH_DOT_COMPONENT"))
  assert_eq(report.pruned_directories, [])
}

///|
test "unicode patterns match unicode paths and are case sensitive" {
  let report = audit_report([file("研究/结果.tmp")], ["研究/*.tmp"])
  assert_eq(report.excluded_entries, 1)
  assert_eq(report.pruned_directories, []) // 研究 still holds retained siblings
  let case_report = audit_report([file("Data/a"), file("data/b")], ["data/*"])
  assert_eq(case_report.excluded_entries, 1) // only data/b matches
  assert_eq(case_report.pruned_directories, [])
}

///|
test "pruned set is minimal: a pruned ancestor subsumes deeper matches" {
  let report = audit_report(
    [file("build-debug/nested/out.bin"), file("src/a.txt")],
    ["build-*"],
  )
  assert_eq(report.excluded_entries, 1)
  assert_eq(report.pruned_directories, ["build-debug"])
  assert_eq(report.summary.entries, 1)
}

///|
test "a full-path pattern prunes only the designated directory" {
  let report = audit_report(
    [directory("cache"), file("cache/data/out.bin"), file("release/a.txt")],
    ["cache/data"],
  )
  // The cache directory itself is retained; only cache/data is pruned.
  assert_eq(report.excluded_entries, 1)
  assert_eq(report.pruned_directories, ["cache/data"])
}

///|
test "empty scope leaves every entry and the report untouched" {
  let entries = [file("a.txt"), directory("b")]
  let report = audit_report(entries, [])
  assert_eq(report.excluded_entries, 0)
  assert_eq(report.pruned_directories, [])
  assert_eq(report.scope, [])
  assert_eq(report.summary.entries, 2)
  let plain = @moonportcheck.audit_with_options(
    entries,
    @moonportcheck.default_audit_options(),
  )
  assert_eq(report.summary, plain.summary)
  assert_eq(report.diagnostics, plain.diagnostics)
}

///|
test "scan issues keep scope fields when attached" {
  let report = audit_report([file("a.tmp"), file("b.txt")], ["*.tmp"])
  let combined = @moonportcheck.with_scan_issues(report, [
    {
      code: "SCAN_IO_ERROR",
      path: "locked",
      message: "Cannot enumerate directory (EACCES).",
    },
  ])
  assert_eq(combined.excluded_entries, 1)
  assert_eq(combined.scope, ["*.tmp"])
  assert_eq(combined.pruned_directories, [])
  assert_eq(combined.complete, false)
  assert_eq(combined.scan_issues.length(), 1)
}

///|
test "exclusion result is independent of input and pattern order" {
  let patterns = ["b*", "#tmp", "*/tmp", "c/"]
  let entries = [file("x"), file("b1"), file("b2")]
  let first = audit_report(entries, patterns)
  let second = audit_report(entries.rev(), patterns.rev())
  assert_eq(first.excluded_entries, second.excluded_entries)
  assert_eq(first.summary, second.summary)
  assert_eq(first.pruned_directories, second.pruned_directories)
  assert_eq(first.scope, second.scope)
}
