///|
fn detailed(
  entries : Array[@moonportcheck.PathEntry],
) -> @moonportcheck.DetailedReport {
  @moonportcheck.audit_with_options(
    entries,
    @moonportcheck.default_audit_options(),
  )
}

///|
fn detailed_find(
  report : @moonportcheck.DetailedReport,
  code : String,
  anchor : String,
) -> @moonportcheck.DetailedDiagnostic raise {
  for item in report.diagnostics {
    if item.code == code && item.anchor == anchor {
      return item
    }
  }
  fail("Expected diagnostic " + code + " at " + anchor)
}

///|
test "detailed report is schema two with explicit empty scope and preserved v1 fields" {
  let entries = files([
    "Data/a", "data/b", "CON.txt", "CON.txt", "a", "a/child", "../bad",
  ])
  let old = @moonportcheck.audit(entries)
  let report = detailed(entries)
  assert_eq(report.schema_version, 2)
  assert_eq(report.profile, old.profile)
  assert_eq(report.source, "manifest")
  assert_true(report.complete)
  @test.assert_eq(report.summary, old.summary)
  @test.assert_eq(report.limitations, old.limitations)
  @test.assert_eq(report.scope, [])
  assert_eq(report.excluded_entries, 0)
  @test.assert_eq(report.pruned_directories, [])
  @test.assert_eq(report.scan_issues, [])
  let projected : Array[@moonportcheck.Diagnostic] = report.diagnostics.map(d => {
    code: d.code,
    severity: d.severity,
    paths: d.paths,
    occurrences: d.occurrences,
    message: d.message,
  })
  @test.assert_eq(projected, old.diagnostics)
  @test.assert_eq(@moonportcheck.audit(entries), old)
}

///|
test "implicit directory conflict retains actual source paths and duplicate counts" {
  let report = detailed(
    files(["artifact", "artifact/report.txt", "artifact/report.txt"]),
  )
  let conflict = detailed_find(report, "PATH_KIND_CONFLICT", "artifact")
  @test.assert_eq(conflict.paths, ["artifact"])
  assert_eq(conflict.occurrences, 1)
  @test.assert_eq(conflict.members, [
    { path: "artifact", kind: @moonportcheck.File, count: 1, },
    { path: "artifact/report.txt", kind: @moonportcheck.File, count: 2, },
  ])
  @test.assert_eq(conflict.source_examples, conflict.members)
  assert_eq(conflict.source_total, 2)
  assert_false(conflict.sources_truncated)
  assert_eq(conflict.group_key, "[\"PATH_KIND_CONFLICT\",\"artifact\"]")
}

///|
test "members distinguish same-path kinds and preserve per-kind occurrence counts" {
  let report = detailed([
    { path: "same", kind: @moonportcheck.File, },
    { path: "same", kind: @moonportcheck.Directory, },
    { path: "same", kind: @moonportcheck.File, },
  ])
  for code in ["PATH_DUPLICATE", "PATH_KIND_CONFLICT"] {
    let group = detailed_find(report, code, "same")
    @test.assert_eq(group.members, [
      { path: "same", kind: @moonportcheck.Directory, count: 1, },
      { path: "same", kind: @moonportcheck.File, count: 2, },
    ])
    assert_eq(group.source_total, 2)
    assert_false(group.sources_truncated)
  }
  assert_eq(detailed_find(report, "PATH_DUPLICATE", "same").occurrences, 3)
  assert_eq(detailed_find(report, "PATH_KIND_CONFLICT", "same").occurrences, 1)
}

///|
test "case samples retain both prefix spellings instead of first five sources" {
  let entries = files(Array::makei(100, i => "A/" + i.to_string()))
  entries.push({ path: "a/z", kind: @moonportcheck.File, })
  let group = detailed_find(detailed(entries), "PATH_CASE_COLLISION", "a")
  assert_eq(group.members.length(), 101)
  assert_eq(group.source_total, 101)
  assert_eq(group.source_examples.length(), 5)
  assert_true(group.sources_truncated)
  assert_true(group.source_examples.any(m => m.path == "a/z"))
  assert_true(group.source_examples.any(m => m.path.has_prefix("A/")))
}

///|
test "kind samples retain file and implicit directory roles even when all sources are files" {
  let entries = files(Array::makei(100, i => "A/" + i.to_string()))
  entries.push({ path: "a", kind: @moonportcheck.File, })
  let group = detailed_find(detailed(entries), "PATH_KIND_CONFLICT", "a")
  assert_eq(group.members.length(), 101)
  assert_eq(group.source_examples.length(), 5)
  assert_true(group.source_examples.any(m => m.path == "a"))
  assert_true(group.source_examples.any(m => m.path.has_prefix("A/")))
  assert_true(group.source_examples.all(m => m.kind == @moonportcheck.File))
}

///|
test "group identity stays fixed when collision members or counts increase" {
  let before = detailed_find(
    detailed(files(["Data/a", "data/b"])),
    "PATH_CASE_COLLISION",
    "data",
  )
  let after = detailed_find(
    detailed(files(["Data/a", "data/b", "DATA/c", "Data/a"])),
    "PATH_CASE_COLLISION",
    "data",
  )
  assert_eq(before.group_key, after.group_key)
  assert_eq(before.anchor, after.anchor)
  assert_eq(after.members.length(), 3)
  assert_eq(after.members[1].count, 2)
}

///|
test "schema two groups sort by stable folded anchor instead of current prefix spelling" {
  let before = detailed(files(["daTa/x", "data/y", "ZOO/u", "Zoo/v"]))
  @test.assert_eq(before.diagnostics.map(d => d.anchor), ["data", "zoo"])
  let after = detailed(files(["daTa/x", "data/y", "DATA/z", "ZOO/u", "Zoo/v"]))
  @test.assert_eq(
    before.diagnostics.map(d => d.group_key),
    after.diagnostics.map(d => d.group_key),
  )
}

///|
test "structurally invalid paths do not contribute to otherwise real hierarchy conflicts" {
  let report = detailed(files(["a", "A/ok", "a/../x", "a//x", "a/"]))
  let conflict = detailed_find(report, "PATH_KIND_CONFLICT", "a")
  @test.assert_eq(conflict.members.map(m => m.path), ["A/ok", "a"])
  let invalid = detailed_find(report, "PATH_DOT_COMPONENT", "a/../x")
  @test.assert_eq(invalid.members.map(m => m.path), ["a/../x"])
}

///|
test "all detailed evidence and both formats are stable under input permutation" {
  let entries = files([
    "Z/a", "z/b", "z/b", "CON.txt", "root", "root/child", "bad\nname",
  ])
  let normal = detailed(entries)
  let reversed = detailed(entries.rev())
  @test.assert_eq(normal, reversed)
  assert_eq(
    @moonportcheck.render_detailed_json(normal),
    @moonportcheck.render_detailed_json(reversed),
  )
  assert_eq(
    @moonportcheck.render_detailed_text(normal),
    @moonportcheck.render_detailed_text(reversed),
  )
  let text = @moonportcheck.render_detailed_text(normal)
  assert_true(text.contains("bad\\nname"))
  assert_false(text.contains("bad\nname"))
  let json = @moonportcheck.render_detailed_json(normal)
  let parsed = @json.parse(json) catch { _ => fail("Detailed JSON must parse") }
  guard parsed is Object(fields) else {
    fail("Detailed JSON must be an object")
  }
  @test.assert_eq(fields.get("schema_version"), Some((2).to_json()))
  assert_true(fields.get("scan_issues") is Some(Array(_)))
  assert_true(fields.get("scope") is Some(Array(_)))
}

///|
test "scan failures remain separate from path evidence and force incomplete status" {
  let original = detailed(files(["CON.txt"]))
  let issues : Array[@moonportcheck.ScanIssue] = [
    { code: "SCAN_LINK_SKIPPED", path: "link", message: "Link skipped.", },
    {
      code: "SCAN_IO_ERROR",
      path: "locked",
      message: "Cannot enumerate directory.",
    },
  ]
  let report = @moonportcheck.with_scan_issues(original, issues)
  assert_eq(report.source, "scan")
  assert_false(report.complete)
  assert_eq(report.summary.scan_issues, 2)
  assert_eq(report.summary.diagnostic_groups, 1)
  @test.assert_eq(report.diagnostics, original.diagnostics)
  @test.assert_eq(report.scan_issues.map(i => i.code), [
    "SCAN_IO_ERROR", "SCAN_LINK_SKIPPED",
  ])
  assert_true(
    @moonportcheck.render_detailed_text(report).contains("INCOMPLETE"),
  )
  assert_true(
    @moonportcheck.render_detailed_text(report).contains("SCAN_LINK_SKIPPED"),
  )
  assert_eq(
    @moonportcheck.render_detailed_json(report),
    @moonportcheck.render_detailed_json(
      @moonportcheck.with_scan_issues(original, issues.rev()),
    ),
  )
  assert_true(original.complete)
  assert_eq(original.scan_issues.length(), 0)
}

///|
test "complete scan with zero issues is not falsely incomplete" {
  let report = @moonportcheck.with_scan_issues(detailed([]), [])
  assert_eq(report.source, "scan")
  assert_true(report.complete)
  assert_eq(report.summary.scan_issues, 0)
  assert_true(@moonportcheck.render_detailed_text(report).contains("PASS"))
}

///|
test "detailed markdown renders finding cells and escapes hostile paths" {
  let report = detailed(files(["a|b.txt.", "CON.txt"]))
  let md = @moonportcheck.render_detailed_markdown(report)
  assert_true(md.has_prefix("# MoonPortCheck report"))
  assert_true(md.contains("**Status:** `FINDINGS`"))
  assert_true(md.contains("## Findings"))
  assert_true(md.contains("| `NAME_RESERVED` | `CON.txt` |"))
  assert_true(md.contains("`a\\|b.txt.`"))
  // Rendering is deterministic, and this is a report table, not a diff table.
  assert_eq(md, @moonportcheck.render_detailed_markdown(report))
  assert_eq(md.contains("| Kind | Path | Details |"), false)
}

///|
test "detailed markdown reports incomplete status and scan issues" {
  let report = @moonportcheck.with_scan_issues(detailed([]), [
    issue("SCAN_IO_ERROR", "logs/x", "Cannot read entry."),
  ])
  let md = @moonportcheck.render_detailed_markdown(report)
  assert_true(md.contains("**Status:** `INCOMPLETE`"))
  assert_true(md.contains("## Scan issues"))
  assert_true(md.contains("## Coverage limits"))
  assert_true(
    md.contains("| `SCAN_IO_ERROR` | `logs/x` | Cannot read entry. |"),
  )
  assert_true(md.contains("No findings."))
}

///|
test "detailed markdown renders a clean report without table rows" {
  let md = @moonportcheck.render_detailed_markdown(detailed(files(["ok.txt"])))
  assert_true(md.contains("**Status:** `PASS (covered rules only)`"))
  assert_true(md.contains("No findings."))
  assert_true(md.contains("No scan issues."))
}
