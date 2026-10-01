///|
fn baseline_of(
  report : @moonportcheck.DetailedReport,
) -> @moonportcheck.Baseline raise {
  match @moonportcheck.build_baseline(report) {
    Err(e) => fail(e.code + ": " + e.message)
    Ok(baseline) => baseline
  }
}

///|
fn baseline_error(report : @moonportcheck.DetailedReport) -> String raise {
  match @moonportcheck.build_baseline(report) {
    Err(e) => e.code
    Ok(_) => fail("Expected a baseline error")
  }
}

///|
fn baseline_find(
  baseline : @moonportcheck.Baseline,
  code : String,
  anchor : String,
) -> @moonportcheck.BaselineGroup raise {
  for group in baseline.groups {
    if group.code == code && group.anchor == anchor {
      return group
    }
  }
  fail("Expected baseline group " + code + " at " + anchor)
}

///|
fn baseline_change_keys(diff : @moonportcheck.BaselineDiff) -> Array[String] {
  diff.changes.map(change => {
    let name = match change.status {
      New => "new"
      Worsened => "worsened"
      Existing => "existing"
      Resolved => "resolved"
    }
    name + "@" + change.code + "@" + change.anchor
  })
}

///|
test "baseline requires a complete schema 2 report" {
  let empty = baseline_of(detailed([]))
  assert_eq(empty.format, "moonportcheck-baseline")
  assert_eq(empty.schema_version, 1)
  assert_eq(empty.profile, "portable-windows-v1")
  assert_eq(empty.rules_version, "1")
  @test.assert_eq(empty.scope, [])
  assert_eq(empty.groups.length(), 0)
  let incomplete = @moonportcheck.with_scan_issues(detailed([]), [
    issue("SCAN_IO_ERROR", "x", "Cannot read."),
  ])
  assert_eq(baseline_error(incomplete), "INPUT_INCOMPLETE")
  let v1 : @moonportcheck.DetailedReport = {
    schema_version: 1,
    profile: "portable-windows-v1",
    source: "manifest",
    complete: true,
    summary: {
      entries: 0,
      files: 0,
      directories: 0,
      diagnostic_groups: 0,
      scan_issues: 0,
    },
    diagnostics: [],
    limitations: [],
    scan_issues: [],
    scope: [],
    excluded_entries: 0,
    pruned_directories: [],
  }
  assert_eq(baseline_error(v1), "INPUT_SCHEMA")
}

///|
test "baseline binds profile scope rules version and sorted groups" {
  let baseline = baseline_of(
    @moonportcheck.audit_with_exclusions(
      files(["Data/a", "data/b", "CON.txt"]),
      @moonportcheck.default_audit_options(),
      parsed_scope(["*.tmp"]),
    ),
  )
  @test.assert_eq(baseline.scope, ["*.tmp"])
  assert_eq(baseline.groups.length(), 2)
  let collision = baseline_find(baseline, "PATH_CASE_COLLISION", "data")
  @test.assert_eq(collision.members, [
    { path: "Data/a", kind: @moonportcheck.File, count: 1, },
    { path: "data/b", kind: @moonportcheck.File, count: 1, },
  ])
  assert_eq(collision.source_total, 2)
  let reserved = baseline_find(baseline, "NAME_RESERVED", "CON.txt")
  @test.assert_eq(reserved.members, [
    { path: "CON.txt", kind: @moonportcheck.File, count: 1, },
  ])
  assert_eq(reserved.source_total, 1)
}

///|
test "classification keeps stable existing groups and resolves only gone groups" {
  let baseline = baseline_of(
    detailed(
      files(["Data/a", "data/b", "data/z.txt", "data/CON.txt", "z/CON.txt"]),
    ),
  )
  let diff = @moonportcheck.diff_with_baseline(
    baseline,
    detailed(files(["Data/a", "data/b", "z/CON.txt"])),
  )
  @test.assert_eq(baseline_change_keys(diff), [
    "existing@NAME_RESERVED@z/CON.txt", "existing@PATH_CASE_COLLISION@data", "resolved@NAME_RESERVED@data/CON.txt",
  ])
}

///|
test "classification reports new members and fresh groups as worsened and new" {
  let baseline = baseline_of(detailed(files(["Data/a", "data/b"])))
  let diff = @moonportcheck.diff_with_baseline(
    baseline,
    detailed(files(["Data/a", "data/b", "DATA/c.txt", "CON.txt"])),
  )
  @test.assert_eq(baseline_change_keys(diff), [
    "new@NAME_RESERVED@CON.txt", "worsened@PATH_CASE_COLLISION@data",
  ])
}

///|
test "baseline and classification render byte-stable documents" {
  let baseline = baseline_of(
    @moonportcheck.audit_with_exclusions(
      files(["a/CON.txt"]),
      @moonportcheck.default_audit_options(),
      parsed_scope(["*.tmp"]),
    ),
  )
  assert_eq(
    @moonportcheck.render_baseline_json(baseline),
    "{\"format\":\"moonportcheck-baseline\",\"schema_version\":1,\"profile\":\"portable-windows-v1\",\"rules_version\":\"1\",\"scope\":[\"*.tmp\"],\"groups\":[{\"code\":\"NAME_RESERVED\",\"anchor\":\"a/CON.txt\",\"members\":[{\"path\":\"a/CON.txt\",\"kind\":\"file\",\"count\":1}],\"source_total\":1}]}",
  )
  let diff = @moonportcheck.diff_with_baseline(
    baseline,
    detailed(files(["a/CON.txt"])),
  )
  assert_eq(
    @moonportcheck.render_baseline_diff_json(diff),
    "{\"format\":\"moonportcheck-baseline-diff\",\"schema_version\":1,\"changes\":[{\"code\":\"NAME_RESERVED\",\"anchor\":\"a/CON.txt\",\"status\":\"existing\",\"members\":[{\"path\":\"a/CON.txt\",\"kind\":\"file\",\"count\":1}],\"source_total\":1}]}",
  )
  assert_eq(
    @moonportcheck.render_baseline_diff_text(diff),
    "[existing] NAME_RESERVED@a/CON.txt (current_source_total=1)\n",
  )
}

///|
test "baseline and schema 2 reports parse back to equal values" {
  let report = detailed(files(["Data/a", "data/b", "CON.txt"]))
  let parsed_report = match
    @moonportcheck.parse_detailed_report(
      @moonportcheck.render_detailed_json(report),
    ) {
    Err(e) => fail(e.code + ": " + e.message)
    Ok(parsed) => parsed
  }
  @test.assert_eq(parsed_report, report)
  let baseline = baseline_of(report)
  let parsed_baseline = match
    @moonportcheck.parse_baseline(@moonportcheck.render_baseline_json(baseline)) {
    Err(e) => fail(e.code + ": " + e.message)
    Ok(parsed) => parsed
  }
  @test.assert_eq(parsed_baseline, baseline)
}

///|
fn add_unknown_field(value : Json) -> Unit raise {
  guard value is Object(fields) else { fail("Expected an object") }
  fields["unexpected"] = true.to_json()
}

///|
test "baseline strict fields reject top group and member extensions" {
  let text = @moonportcheck.render_baseline_json(
    baseline_of(detailed(files(["CON"]))),
  )
  for level in ["top", "group", "member"] {
    let value = @json.parse(text) catch { _ => fail("Invalid fixture") }
    guard value is Object(fields) else { fail("Expected baseline") }
    guard fields.get("groups") is Some(Array(groups)) else {
      fail("Expected groups")
    }
    guard groups[0] is Object(group) else { fail("Expected group") }
    guard group.get("members") is Some(Array(members)) else {
      fail("Expected members")
    }
    add_unknown_field(
      if level == "top" {
        value
      } else if level == "group" {
        groups[0]
      } else {
        members[0]
      },
    )
    match @moonportcheck.parse_baseline(value.stringify()) {
      Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
      Ok(_) => fail("Unknown baseline field accepted at " + level)
    }
  }
}

///|
test "report strict fields reject nested extensions and allow baseline metadata" {
  let report = @moonportcheck.with_scan_issues(detailed(files(["CON"])), [
    issue("SCAN_IO_ERROR", "x", "Failed."),
  ])
  let text = @moonportcheck.render_detailed_json(report)
  for level in ["top", "summary", "diagnostic", "member", "example", "issue"] {
    let value = @json.parse(text) catch { _ => fail("Invalid fixture") }
    guard value is Object(fields) else { fail("Expected report") }
    guard fields.get("diagnostics") is Some(Array(diagnostics)) else {
      fail("Expected diagnostics")
    }
    guard diagnostics[0] is Object(diagnostic) else {
      fail("Expected diagnostic")
    }
    guard diagnostic.get("members") is Some(Array(members)) else {
      fail("Expected members")
    }
    guard diagnostic.get("source_examples") is Some(Array(examples)) else {
      fail("Expected examples")
    }
    guard fields.get("scan_issues") is Some(Array(issues)) else {
      fail("Expected issues")
    }
    let target = match level {
      "top" => value
      "summary" => fields["summary"]
      "diagnostic" => diagnostics[0]
      "member" => members[0]
      "example" => examples[0]
      _ => issues[0]
    }
    add_unknown_field(target)
    match @moonportcheck.parse_detailed_report(value.stringify()) {
      Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
      Ok(_) => fail("Unknown report field accepted at " + level)
    }
  }
  let value = @json.parse(text) catch { _ => fail("Invalid fixture") }
  guard value is Object(fields) else { fail("Expected report") }
  fields["baseline"] = @json.parse("{\"changes\":[]}") catch {
    _ => fail("Invalid metadata")
  }
  match @moonportcheck.parse_detailed_report(value.stringify()) {
    Ok(parsed) => assert_eq(parsed, report)
    Err(error) => fail(error.message)
  }
}
