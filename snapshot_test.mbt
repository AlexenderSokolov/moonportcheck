///| Test the snapshot model, canonicalization and strict parsing.

///|
fn snapshot_of(
  entries : Array[@moonportcheck.PathEntry],
  issues : Array[@moonportcheck.ScanIssue],
  scope : Array[String],
) -> @moonportcheck.Snapshot raise {
  match @moonportcheck.build_snapshot(entries, issues, scope) {
    Ok(snapshot) => snapshot
    Err(error) => fail("Valid snapshot rejected: " + error.message)
  }
}

///|
fn audit_snapshot_of(
  snapshot : @moonportcheck.Snapshot,
  extra : Array[String],
) -> @moonportcheck.DetailedReport raise {
  match @moonportcheck.audit_snapshot(snapshot, extra) {
    Ok(report) => report
    Err(error) => fail("Snapshot audit rejected: " + error.message)
  }
}

///|
fn snap_file(path : String) -> @moonportcheck.PathEntry {
  { path, kind: @moonportcheck.File, }
}

///|
fn snap_directory(path : String) -> @moonportcheck.PathEntry {
  { path, kind: @moonportcheck.Directory, }
}

///|
fn issue(
  code : String,
  path : String,
  message : String,
) -> @moonportcheck.ScanIssue {
  { code, path, message, }
}

///|
fn round_trip(
  snapshot : @moonportcheck.Snapshot,
) -> @moonportcheck.Snapshot raise {
  let text = @moonportcheck.render_snapshot_json(snapshot)
  match @moonportcheck.parse_snapshot(text) {
    Ok(parsed) => parsed
    Err(error) => fail("Round trip rejected: " + error.message)
  }
}

///|
test "build_snapshot canonicalizes scope and entries" {
  let snapshot = snapshot_of(
    [
      snap_file("b"),
      snap_directory("a/x"),
      snap_file("a"),
      snap_file("中文"),
      snap_file("b"),
    ],
    [],
    ["cache/", "*.tmp", "cache", "cache/"],
  )
  assert_eq(snapshot.scope, ["*.tmp", "cache", "cache/"])
  assert_eq(snapshot.entries, [
    { path: "a", kind: @moonportcheck.File, },
    { path: "a/x", kind: @moonportcheck.Directory, },
    { path: "b", kind: @moonportcheck.File, },
    { path: "中文", kind: @moonportcheck.File, },
  ])
  assert_true(snapshot.complete)
  assert_eq(snapshot.profile, "portable-windows-v1")
}

///|
test "build_snapshot records and sorts scan issues and completeness" {
  let snapshot = snapshot_of(
    [snap_file("a"), snap_file("b")],
    [
      issue("SCAN_LINK_SKIPPED", "link", "Link was not followed."),
      issue("SCAN_IO_ERROR", "z", "Read failed."),
    ],
    [],
  )
  assert_false(snapshot.complete)
  assert_eq(snapshot.scan_issues, [
    issue("SCAN_IO_ERROR", "z", "Read failed."),
    issue("SCAN_LINK_SKIPPED", "link", "Link was not followed."),
  ])
}

///|
test "build_snapshot rejects conflicting kinds and bad scope patterns" {
  match
    @moonportcheck.build_snapshot([snap_file("x"), snap_directory("x")], [], []) {
    Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
    Ok(_) => fail("Conflicting kinds accepted")
  }
  match @moonportcheck.build_snapshot([snap_file("x")], [], ["bad\\pattern"]) {
    Err(error) => assert_eq(error.code, "PATTERN_INVALID")
    Ok(_) => fail("Invalid scope pattern accepted")
  }
}

///|
test "snapshot round-trips through parse and render" {
  let built = snapshot_of(
    [snap_file("目录/结果.bin"), snap_directory("数据"), snap_file("a")],
    [issue("SCAN_LINK_SKIPPED", "link", "Link was not followed.")],
    ["cache/", "*.tmp"],
  )
  let text = @moonportcheck.render_snapshot_json(built)
  assert_eq(round_trip(built), built)
  assert_eq(@moonportcheck.render_snapshot_json(round_trip(built)), text)
  assert_true(
    text.has_prefix("{\"format\":\"moonportcheck-snapshot\",\"version\":1,"),
  )
}

///|
test "an empty snapshot is complete and round-trips" {
  let built = snapshot_of([], [], [])
  assert_true(built.complete)
  assert_true(built.entries.is_empty())
  assert_eq(round_trip(built), built)
}

///|
test "unicode and case-variant paths survive snapshots" {
  let built = snapshot_of(
    [snap_file("é/y"), snap_file("É/x"), snap_directory("文件夹")],
    [],
    [],
  )
  let sorted = built.entries.map(entry => entry.path)
  assert_eq(sorted, ["É/x", "é/y", "文件夹"])
  assert_eq(round_trip(built), built)
}

///|
test "parse_snapshot rejects corrupted and non-canonical input" {
  let valid = "{\"format\":\"moonportcheck-snapshot\",\"version\":1," +
    "\"profile\":\"portable-windows-v1\",\"complete\":true,\"scope\":[]," +
    "\"entries\":[{\"path\":\"a\",\"kind\":\"file\"}],\"scan_issues\":[]}"
  for
    bad in [
      "not json", "[]", "{\"format\":\"other\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":[],\"entries\":[],\"scan_issues\":[]}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":2,\"profile\":\"p\",\"complete\":true,\"scope\":[],\"entries\":[],\"scan_issues\":[]}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":[],\"entries\":[],\"scan_issues\":[],\"extra\":1}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":\"x\",\"entries\":[],\"scan_issues\":[]}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":[],\"entries\":[{\"path\":\"b\",\"kind\":\"folder\"}],\"scan_issues\":[]}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":[],\"entries\":[{\"path\":\"b\",\"kind\":\"file\"},{\"path\":\"a\",\"kind\":\"file\"}],\"scan_issues\":[]}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":[],\"entries\":[{\"path\":\"a\",\"kind\":\"file\"},{\"path\":\"a\",\"kind\":\"file\"}],\"scan_issues\":[]}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":[],\"entries\":[],\"scan_issues\":[{\"code\":1}]}",
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"p\",\"complete\":true,\"scope\":[\"a[b]\"],\"entries\":[],\"scan_issues\":[]}",
    ] {
    match @moonportcheck.parse_snapshot(bad) {
      Err(_) => ()
      Ok(_) => fail("Corrupted snapshot accepted: " + bad)
    }
  }
  match @moonportcheck.parse_snapshot(valid) {
    Ok(snapshot) => {
      assert_true(snapshot.complete)
      assert_eq(snapshot.entries.length(), 1)
    }
    Err(error) => fail("Valid snapshot rejected: " + error.message)
  }
}

///|
test "audit_snapshot_inherits_scope_and_shrinks" {
  let snapshot = snapshot_of(
    [snap_file("cache/x.bin"), snap_file("ok.txt")],
    [],
    ["cache/"],
  )
  let report = audit_snapshot_of(snapshot, ["ok.txt"])
  assert_true(report.complete)
  assert_eq(report.source, "snapshot")
  assert_eq(report.scope.join(","), "cache/,ok.txt")
  assert_eq(report.summary.entries, 0)
  assert_eq(report.summary.files, 0)
  let inherited = audit_snapshot_of(snapshot, [])
  assert_eq(inherited.scope.join(","), "cache/")
  assert_eq(inherited.summary.entries, 1)
  assert_eq(inherited.excluded_entries, 1)
}

///|
test "audit_snapshot_rejects_foreign_profile_and_keeps_issues" {
  let foreign = match
    @moonportcheck.parse_snapshot(
      "{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"other\",\"complete\":true,\"scope\":[],\"entries\":[],\"scan_issues\":[]}",
    ) {
    Ok(snapshot) => snapshot
    Err(error) => fail("Foreign snapshot rejected: " + error.message)
  }
  match @moonportcheck.audit_snapshot(foreign, []) {
    Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
    Ok(_) => fail("Foreign profile accepted")
  }
  let partial = snapshot_of(
    [snap_file("x.txt")],
    [issue("SCAN_LINK_SKIPPED", "x.txt", "Not followed.")],
    [],
  )
  let report = audit_snapshot_of(partial, [])
  assert_false(report.complete)
  assert_eq(report.summary.scan_issues, 1)
  assert_eq(report.scan_issues.length(), 1)
}
