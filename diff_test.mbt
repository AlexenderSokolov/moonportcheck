///| Test the snapshot diff core: matching order, kinds, folding and stability.

///|
fn diff_of(
  before : @moonportcheck.Snapshot,
  after : @moonportcheck.Snapshot,
) -> @moonportcheck.SnapshotDiff raise {
  match @moonportcheck.diff_snapshots(before, after) {
    Ok(diff) => diff
    Err(error) => fail("Snapshot diff rejected: " + error.message)
  }
}

///|
fn change_keys(diff : @moonportcheck.SnapshotDiff) -> Array[String] {
  diff.changes.map(change => {
    let kind_name = match change.kind {
      Added => "added"
      Removed => "removed"
      KindChanged => "kind"
      CaseChanged => "case"
    }
    kind_name +
    ":" +
    change.path +
    (if change.paired_with == "" { "" } else { "~" + change.paired_with })
  })
}

///|
test "diff_identical_snapshots_has_no_changes" {
  let snapshot = snapshot_of(
    [snap_file("a.txt"), snap_directory("dir"), snap_file("dir/x.bin")],
    [],
    ["*.tmp"],
  )
  let diff = diff_of(snapshot, snapshot)
  assert_true(diff.complete)
  assert_eq(diff.changes.length(), 0)
  assert_eq(change_keys(diff), [])
}

///|
test "diff_reports_added_removed_and_kind_changes_in_stable_order" {
  let before = snapshot_of(
    [
      snap_file("data/a.txt"),
      snap_file("b.txt"),
      snap_file("C.txt"),
      snap_directory("dir"),
    ],
    [],
    [],
  )
  let after = snapshot_of(
    [
      snap_file("A.txt"),
      snap_file("b.txt"),
      snap_directory("dir"),
      snap_file("d.tmp"),
      snap_directory("C.txt"),
    ],
    [],
    [],
  )
  let diff = diff_of(before, after)
  assert_eq(change_keys(diff), [
    "added:A.txt", "added:d.tmp", "removed:data/a.txt", "kind:C.txt",
  ])
}

///|
test "diff_marks_one_to_one_same_kind_fold_as_case_change" {
  let before = snapshot_of([snap_file("report.txt")], [], [])
  let after = snapshot_of([snap_file("Report.txt")], [], [])
  let diff = diff_of(before, after)
  assert_eq(change_keys(diff), ["case:Report.txt~report.txt"])
  assert_eq(diff.changes[0].before_kind, "file")
  assert_eq(diff.changes[0].after_kind, "file")
}

///|
test "diff_never_flags_kind_mismatch_or_ambiguous_folds_as_case" {
  let kind_before = snapshot_of([snap_file("a.txt")], [], [])
  let kind_after = snapshot_of([snap_directory("A.txt")], [], [])
  assert_eq(change_keys(diff_of(kind_before, kind_after)), [
    "added:A.txt", "removed:a.txt",
  ])
  let ambiguous_before = snapshot_of(
    [snap_file("a.txt"), snap_file("A.txt")],
    [],
    [],
  )
  let ambiguous_after = snapshot_of([snap_file("a.TXT")], [], [])
  assert_eq(change_keys(diff_of(ambiguous_before, ambiguous_after)), [
    "added:a.TXT", "removed:A.txt", "removed:a.txt",
  ])
}

///|
test "diff_rejects_mismatched_scopes_and_keeps_completeness" {
  let left = snapshot_of([snap_file("x.txt")], [], ["*.tmp"])
  let right = snapshot_of([snap_file("x.txt")], [], [])
  match @moonportcheck.diff_snapshots(left, right) {
    Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
    Ok(_) => fail("Mismatched scopes accepted")
  }
  let partial = snapshot_of(
    [snap_file("x.txt")],
    [issue("SCAN_LINK_SKIPPED", "x.txt", "Not followed.")],
    [],
  )
  let diff = diff_of(partial, snapshot_of([snap_file("x.txt")], [], []))
  assert_false(diff.complete)
  assert_eq(diff.changes.length(), 0)
}

///|
test "diff_render_is_stable" {
  let before = snapshot_of([snap_file("b.txt"), snap_file("a.txt")], [], [])
  let after = snapshot_of([snap_file("a2.txt")], [], [])
  let diff = diff_of(before, after)
  assert_eq(
    @moonportcheck.render_snapshot_diff_json(diff),
    "{\"format\":\"moonportcheck-diff\",\"version\":1,\"complete\":true,\"changes\":[{\"kind\":\"added\",\"path\":\"a2.txt\",\"paired_with\":\"\",\"before_kind\":\"\",\"after_kind\":\"file\"},{\"kind\":\"removed\",\"path\":\"a.txt\",\"paired_with\":\"\",\"before_kind\":\"file\",\"after_kind\":\"\"},{\"kind\":\"removed\",\"path\":\"b.txt\",\"paired_with\":\"\",\"before_kind\":\"file\",\"after_kind\":\"\"}]}",
  )
}

///|
test "diff_text_renders_stable_human_output" {
  let diff = diff_of(
    snapshot_of([snap_file("b.txt"), snap_file("a.txt")], [], []),
    snapshot_of([snap_file("a2.txt")], [], []),
  )
  assert_eq(
    @moonportcheck.render_snapshot_diff_text(diff),
    "+ a2.txt (added, file)\n" +
    "- a.txt (removed, file)\n" +
    "- b.txt (removed, file)\n",
  )
  let partial = snapshot_of(
    [snap_file("x.txt")],
    [issue("SCAN_LINK_SKIPPED", "x.txt", "Not followed.")],
    [],
  )
  let warning = diff_of(partial, snapshot_of([snap_file("x.txt")], [], []))
  assert_eq(
    @moonportcheck.render_snapshot_diff_text(warning),
    "INCOMPLETE: the input snapshot is incomplete; the diff is not trustworthy.\nNo differences.\n",
  )
}
