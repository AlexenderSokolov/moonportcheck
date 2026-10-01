///|
/// A kind of change between two snapshots.
pub enum DiffKind {
  Added
  Removed
  KindChanged
  CaseChanged
} derive(Eq, Debug)

///|
pub extend DiffKind with Eq::{equal, not_equal}

///|
pub extend DiffKind with @debug.Debug::{to_repr}

///|
/// Stable serialized name for a change kind.
fn diff_kind_name(kind : DiffKind) -> String {
  match kind {
    Added => "added"
    Removed => "removed"
    KindChanged => "kind"
    CaseChanged => "case"
  }
}

///|
/// Stable serialization rank so the change list has a fixed group order.
fn diff_kind_rank(kind : DiffKind) -> Int {
  match kind {
    Added => 0
    Removed => 1
    KindChanged => 2
    CaseChanged => 3
  }
}

///|
pub struct SnapshotChange {
  kind : DiffKind
  path : String
  paired_with : String
  before_kind : String
  after_kind : String
} derive(Eq, Debug)

///|
pub extend SnapshotChange with Eq::{equal, not_equal}

///|
pub extend SnapshotChange with @debug.Debug::{to_repr}

///|
pub struct SnapshotDiff {
  complete : Bool
  changes : Array[SnapshotChange]
} derive(Eq, Debug)

///|
pub extend SnapshotDiff with Eq::{equal, not_equal}

///|
pub extend SnapshotDiff with @debug.Debug::{to_repr}

///|
fn change_order(a : SnapshotChange, b : SnapshotChange) -> Int {
  let rank_a = diff_kind_rank(a.kind)
  let rank_b = diff_kind_rank(b.kind)
  if rank_a != rank_b {
    return rank_a.compare(rank_b)
  }
  ordinal_compare(a.path, b.path)
}

///|
/// Compare the entries of two snapshots. Exact path pairs come first; the
/// remaining entries are then compared by ASCII folding. A case change is only
/// reported when exactly one before entry folds to exactly one after entry with
/// the same kind. Renames and content changes are never inferred.
pub fn diff_snapshots(
  before : Snapshot,
  after : Snapshot,
) -> Result[SnapshotDiff, InputError] {
  if before.scope.length() != after.scope.length() {
    return Err({
      code: "INPUT_SCHEMA",
      message: "Snapshot scopes differ; cannot diff them.",
    })
  }
  for i in 0..<before.scope.length() {
    if before.scope[i] != after.scope[i] {
      return Err({
        code: "INPUT_SCHEMA",
        message: "Snapshot scopes differ; cannot diff them.",
      })
    }
  }
  let before_kinds : Map[String, EntryKind] = Map([])
  let after_kinds : Map[String, EntryKind] = Map([])
  for entry in before.entries {
    before_kinds[entry.path] = entry.kind
  }
  for entry in after.entries {
    after_kinds[entry.path] = entry.kind
  }
  let remaining_before : Array[(String, EntryKind)] = []
  let remaining_after : Array[(String, EntryKind)] = []
  let changes : Array[SnapshotChange] = []
  for path in sorted_keys(before_kinds) {
    let kind = before_kinds[path]
    match after_kinds.get(path) {
      None => remaining_before.push((path, kind))
      Some(after_kind) =>
        if kind != after_kind {
          changes.push({
            kind: KindChanged,
            path,
            paired_with: "",
            before_kind: source_kind_name(kind),
            after_kind: source_kind_name(after_kind),
          })
        }
    }
  }
  for path in sorted_keys(after_kinds) {
    let kind = after_kinds[path]
    match before_kinds.get(path) {
      None => remaining_after.push((path, kind))
      Some(_) => ()
    }
  }
  let before_folds : Map[String, Array[(String, EntryKind)]] = Map([])
  let after_folds : Map[String, Array[(String, EntryKind)]] = Map([])
  for (path, kind) in remaining_before {
    let folded = ascii_lower(path)
    let list = match before_folds.get(folded) {
      None => []
      Some(list) => list
    }
    before_folds[folded] = list + [(path, kind)]
  }
  for (path, kind) in remaining_after {
    let folded = ascii_lower(path)
    let list = match after_folds.get(folded) {
      None => []
      Some(list) => list
    }
    after_folds[folded] = list + [(path, kind)]
  }
  for folded in sorted_keys(before_folds) {
    let before_list = before_folds[folded]
    match after_folds.get(folded) {
      None =>
        for (path, kind) in before_list {
          changes.push({
            kind: Removed,
            path,
            paired_with: "",
            before_kind: source_kind_name(kind),
            after_kind: "",
          })
        }
      Some(after_list) =>
        if before_list.length() == 1 &&
          after_list.length() == 1 &&
          before_list[0].1 == after_list[0].1 {
          changes.push({
            kind: CaseChanged,
            path: after_list[0].0,
            paired_with: before_list[0].0,
            before_kind: source_kind_name(before_list[0].1),
            after_kind: source_kind_name(after_list[0].1),
          })
        } else {
          for (path, kind) in before_list {
            changes.push({
              kind: Removed,
              path,
              paired_with: "",
              before_kind: source_kind_name(kind),
              after_kind: "",
            })
          }
          for (path, kind) in after_list {
            changes.push({
              kind: Added,
              path,
              paired_with: "",
              before_kind: "",
              after_kind: source_kind_name(kind),
            })
          }
        }
    }
  }
  for folded in sorted_keys(after_folds) {
    if before_folds.get(folded) is None {
      for (path, kind) in after_folds[folded] {
        changes.push({
          kind: Added,
          path,
          paired_with: "",
          before_kind: "",
          after_kind: source_kind_name(kind),
        })
      }
    }
  }
  changes.sort_by(change_order)
  Ok({ complete: before.complete && after.complete, changes, })
}

///|
/// Stable serialization of a snapshot diff with fixed field order.
pub fn render_snapshot_diff_json(diff : SnapshotDiff) -> String {
  "{\"format\":\"moonportcheck-diff\",\"version\":1,\"complete\":" +
  diff.complete.to_json().stringify() +
  ",\"changes\":[" +
  diff.changes
  .map(change => {
    "{\"kind\":" +
    quote(diff_kind_name(change.kind)) +
    ",\"path\":" +
    quote(change.path) +
    ",\"paired_with\":" +
    quote(change.paired_with) +
    ",\"before_kind\":" +
    quote(change.before_kind) +
    ",\"after_kind\":" +
    quote(change.after_kind) +
    "}"
  })
  .join(",") +
  "]}"
}
