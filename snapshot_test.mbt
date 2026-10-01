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
