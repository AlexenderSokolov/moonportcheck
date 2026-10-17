///|
priv struct DpTree {
  entries : Map[String, EntryKind]
  children : Map[String, Array[String]]
}

///|
priv struct DpTask {
  kind : String
  source : String
  origin : DeliveryOrigin
  to : String
  mut done : Bool
  mut staged : Bool
}

///|
fn dp_problem(
  out : Array[DeliveryDiagnostic],
  code : String,
  path : String,
  message : String,
) -> Unit {
  out.push({ code, path, message, step: -1, })
}

///|
fn dp_parent(path : String) -> String {
  match path.rev_split_once("/") {
    Some((parent, _)) => parent.to_owned()
    None => ""
  }
}

///|
fn dp_relative(path : String) -> Bool {
  if path == "" || path.has_prefix("/") || path.contains("\\") {
    return false
  }
  let chars = path.iter().take(2).collect()
  if chars.length() == 2 &&
    chars[1] == ':' &&
    (
      (chars[0] >= 'A' && chars[0] <= 'Z') ||
      (chars[0] >= 'a' && chars[0] <= 'z')
    ) {
    return false
  }
  for component in path.split("/") {
    if component == "" || component == "." || component == ".." {
      return false
    }
    if component.iter().any(c => c.to_int() == 0) {
      return false
    }
  }
  true
}

///|
fn dp_index(
  tree : DeliveryTree,
  diagnostics : Array[DeliveryDiagnostic],
) -> DpTree {
  let entries : Map[String, EntryKind] = Map([])
  let explicit : Map[String, Bool] = Map([])
  for entry in tree.snapshot.entries {
    if !dp_relative(entry.path) {
      dp_problem(
        diagnostics,
        "SOURCE_PATH_INVALID",
        entry.path,
        "A source path must be a normalized relative path.",
      )
      continue
    }
    if explicit.contains(entry.path) {
      dp_problem(
        diagnostics,
        "SOURCE_DUPLICATE",
        entry.path,
        "An initial path occurs more than once.",
      )
    }
    explicit[entry.path] = true
    match entries.get(entry.path) {
      Some(kind) if kind != entry.kind =>
        dp_problem(
          diagnostics,
          "SOURCE_KIND_CONFLICT",
          entry.path,
          "A source path cannot be both a file and a directory.",
        )
      _ => entries[entry.path] = entry.kind
    }
    let mut parent = dp_parent(entry.path)
    while parent != "" {
      match entries.get(parent) {
        Some(File) =>
          dp_problem(
            diagnostics, "SOURCE_KIND_CONFLICT", parent, "An initial file cannot be a parent directory.",
          )
        _ => entries[parent] = Directory
      }
      parent = dp_parent(parent)
    }
  }
  let children : Map[String, Array[String]] = Map([])
  for path in sorted_keys(entries) {
    let parent = dp_parent(path)
    match children.get(parent) {
      Some(paths) => paths.push(path)
      None => children[parent] = [path]
    }
  }
  { entries, children, }
}

///|
fn dp_require_directory(path : String, directories : Map[String, Bool]) -> Unit {
  let mut cursor = path
  while cursor != "" {
    directories[cursor] = true
    cursor = dp_parent(cursor)
  }
}

///|
fn dp_enqueue_watchers(
  slot : String,
  watchers : Map[String, Array[Int]],
  queue : Array[Int],
) -> Unit {
  match watchers.get(slot) {
    Some(waiting) => {
      for task in waiting {
        queue.push(task)
      }
      watchers.remove(slot)
    }
    None => ()
  }
}

///|
/// Plan entirely against initial identities. Slots model portable target names;
/// immutable source indexes retain exact spelling. A wait-list keyed by slots
/// wakes only affected operations, including the parent of a pending mkdir.
pub fn plan_delivery(spec : DeliverySpec) -> Result[DeliveryPlan, InputError] {
  let basis = render_delivery_spec_json(spec)
  let diagnostics : Array[DeliveryDiagnostic] = []
  if spec.target.snapshot.profile != "portable-windows-v1" {
    dp_problem(
      diagnostics,
      "TARGET_PROFILE_UNSUPPORTED",
      spec.target.id,
      "Delivery targets require portable-windows-v1.",
    )
  }
  let trees : Map[String, DpTree] = Map([])
  let mut incomplete = false
  let all_trees = spec.sources.copy()
  all_trees.sort_by((a, b) => {
    let order = ordinal_compare(a.id, b.id)
    if order != 0 {
      order
    } else {
      ordinal_compare(
        render_snapshot_json(a.snapshot),
        render_snapshot_json(b.snapshot),
      )
    }
  })
  all_trees.push(spec.target)
  for tree in all_trees {
    if tree.id == "" || trees.contains(tree.id) {
      dp_problem(
        diagnostics,
        "ROOT_ID_INVALID",
        tree.id,
        "Root ids must be nonempty and unique.",
      )
    }
    if !tree.snapshot.complete ||
      !tree.snapshot.scan_issues.is_empty() ||
      !tree.snapshot.scope.is_empty() {
      incomplete = true
      dp_problem(
        diagnostics,
        "SNAPSHOT_INCOMPLETE",
        tree.id,
        "Delivery requires complete snapshots with empty exclusion scopes.",
      )
    }
    trees[tree.id] = dp_index(tree, diagnostics)
  }
  for issue in audit(spec.target.snapshot.entries).diagnostics {
    dp_problem(diagnostics, issue.code, issue.paths.join(", "), issue.message)
  }
  let initial = trees[spec.target.id]
  let intents : Array[DeliveryIntent] = []
  let directories : Map[String, Bool] = Map([])
  let moved : Map[String, Bool] = Map([])
  let mappings = spec.mappings.copy()
  mappings.sort_by(delivery_mapping_order)
  for mapping in mappings {
    if mapping.mode != "copy" && mapping.mode != "move" {
      dp_problem(
        diagnostics,
        "MAPPING_MODE_INVALID",
        mapping.to,
        "Mapping mode must be copy or move.",
      )
      continue
    }
    guard trees.get(mapping.source) is Some(source) else {
      dp_problem(
        diagnostics,
        "SOURCE_UNKNOWN",
        mapping.source,
        "The mapping source root does not exist.",
      )
      continue
    }
    if mapping.mode == "move" && mapping.source != spec.target.id {
      dp_problem(
        diagnostics,
        "SOURCE_READONLY",
        mapping.from,
        "Only initial target files may be moved.",
      )
      continue
    }
    let kind = if mapping.from == "" {
      Some(Directory)
    } else {
      source.entries.get(mapping.from)
    }
    guard kind is Some(kind) else {
      dp_problem(
        diagnostics,
        "SOURCE_MISSING",
        mapping.from,
        "The mapping source does not exist in the initial snapshot.",
      )
      continue
    }
    if kind == Directory {
      if mapping.mode == "move" {
        dp_problem(
          diagnostics,
          "DIRECTORY_MOVE_UNSUPPORTED",
          mapping.from,
          "Moving a directory is not supported.",
        )
        continue
      }
      if mapping.to != "" {
        dp_require_directory(mapping.to, directories)
      }
      let pending = [mapping.from]
      let mut cursor = 0
      while cursor < pending.length() {
        let path = pending[cursor]
        cursor += 1
        match source.children.get(path) {
          Some(children) =>
            for child in children {
              let suffix = if mapping.from == "" {
                child
              } else {
                child[mapping.from.length() + 1:].to_owned()
              }
              let to = if mapping.to == "" {
                suffix
              } else {
                mapping.to + "/" + suffix
              }
              match source.entries[child] {
                Directory => {
                  dp_require_directory(to, directories)
                  pending.push(child)
                }
                File => {
                  dp_require_directory(dp_parent(to), directories)
                  intents.push({
                    mode: "copy",
                    source: mapping.source,
                    from: child,
                    to,
                    origin: { root: mapping.source, path: child, },
                  })
                }
              }
            }
          None => ()
        }
      }
    } else {
      if mapping.mode == "move" {
        if moved.contains(mapping.from) {
          dp_problem(
            diagnostics,
            "DUPLICATE_MOVE",
            mapping.from,
            "An initial file may be moved at most once.",
          )
        }
        moved[mapping.from] = true
      }
      dp_require_directory(dp_parent(mapping.to), directories)
      intents.push({
        mode: mapping.mode,
        source: mapping.source,
        from: mapping.from,
        to: mapping.to,
        origin: { root: mapping.source, path: mapping.from, },
      })
    }
  }
  intents.sort_by((a, b) => {
    let source = ordinal_compare(a.source, b.source)
    if source != 0 {
      return source
    }
    let from = ordinal_compare(a.from, b.from)
    if from != 0 {
      return from
    }
    let to = ordinal_compare(a.to, b.to)
    if to != 0 {
      return to
    }
    ordinal_compare(a.mode, b.mode)
  })
  // Derive the requested final layout before scheduling. Existing directories
  // cannot disappear; only a mapped initial file is allowed to vacate its slot.
  let final_paths : Map[String, EntryKind] = Map([])
  for path in sorted_keys(initial.entries) {
    let kind = initial.entries[path]
    if kind == Directory || !moved.contains(path) {
      final_paths[path] = kind
    }
  }
  for path in sorted_keys(directories) {
    match final_paths.get(path) {
      Some(File) =>
        dp_problem(
          diagnostics, "TARGET_OCCUPIED", path, "An unmoved initial file blocks a required directory.",
        )
      _ => final_paths[path] = Directory
    }
  }
  for intent in intents {
    if final_paths.contains(intent.to) {
      dp_problem(
        diagnostics,
        "TARGET_OCCUPIED",
        intent.to,
        "A target slot is occupied or requested more than once.",
      )
    } else {
      final_paths[intent.to] = File
    }
  }
  let final_entries : Array[PathEntry] = []
  for path in sorted_keys(final_paths) {
    final_entries.push({ path, kind: final_paths[path], })
  }
  for issue in audit(final_entries).diagnostics {
    dp_problem(diagnostics, issue.code, issue.paths.join(", "), issue.message)
  }
  if incomplete || !diagnostics.is_empty() {
    return Ok({
      status: if incomplete {
        "incomplete"
      } else {
        "blocked"
      },
      basis,
      operations: [],
      temporary_paths: [],
      diagnostics,
    })
  }
  let slots : Map[String, EntryKind] = Map([])
  let positions : Map[String, String] = Map([])
  let reserved_slots : Map[String, Bool] = Map([])
  for tree in trees.values() {
    for path in tree.entries.keys() {
      reserved_slots[ascii_lower(path)] = true
    }
  }
  for path in final_paths.keys() {
    reserved_slots[ascii_lower(path)] = true
  }
  for path in initial.entries.keys() {
    let kind = initial.entries[path]
    slots[ascii_lower(path)] = kind
    if kind == File {
      positions[path] = path
    }
  }
  let empty_origin : DeliveryOrigin = { root: "", path: "", }
  let tasks : Array[DpTask] = []
  for path in sorted_keys(directories) {
    match slots.get(ascii_lower(path)) {
      Some(Directory) => ()
      _ =>
        tasks.push({
          kind: "mkdir",
          source: "",
          origin: empty_origin,
          to: path,
          done: false,
          staged: false,
        })
    }
  }
  let move_tasks : Array[Int] = []
  for intent in intents {
    if intent.mode == "move" && intent.from == intent.to {
      continue
    }
    if intent.mode == "move" {
      move_tasks.push(tasks.length())
    }
    tasks.push({
      kind: intent.mode,
      source: intent.source,
      origin: intent.origin,
      to: intent.to,
      done: false,
      staged: false,
    })
  }
  let watchers : Map[String, Array[Int]] = Map([])
  let queue : Array[Int] = []
  for id in 0..<tasks.length() {
    queue.push(id)
  }
  let operations : Array[DeliveryOperation] = []
  let temporary_paths : Array[String] = []
  let mut queue_cursor = 0
  let mut stage_cursor = 0
  let mut serial = 0
  let mut remaining = tasks.length()
  while remaining > 0 {
    while queue_cursor < queue.length() {
      let id = queue[queue_cursor]
      queue_cursor += 1
      let task = tasks[id]
      if task.done {
        continue
      }
      let parent = ascii_lower(dp_parent(task.to))
      let destination = ascii_lower(task.to)
      let blocker = if parent != "" &&
        !(match slots.get(parent) {
          Some(Directory) => true
          _ => false
        }) {
        parent
      } else if slots.contains(destination) {
        destination
      } else {
        ""
      }
      if blocker != "" {
        match watchers.get(blocker) {
          Some(ids) => ids.push(id)
          None => watchers[blocker] = [id]
        }
        continue
      }
      let from = if task.kind == "mkdir" {
        ""
      } else if task.source == spec.target.id {
        positions[task.origin.path]
      } else {
        task.origin.path
      }
      operations.push({
        kind: task.kind,
        source: task.source,
        from,
        to: task.to,
        origin: task.origin,
      })
      if task.kind == "move" {
        let old = ascii_lower(from)
        slots.remove(old)
        positions[task.origin.path] = task.to
        dp_enqueue_watchers(old, watchers, queue)
      }
      slots[destination] = if task.kind == "mkdir" { Directory } else { File }
      if task.kind == "mkdir" {
        dp_enqueue_watchers(destination, watchers, queue)
      }
      task.done = true
      remaining -= 1
    }
    if remaining == 0 {
      break
    }
    // With an already validated final layout, a stalled queue is a cycle of
    // initial moving files (possibly through directory creation). Vacating one
    // such file preserves its identity and releases its subscribed dependents.
    while stage_cursor < move_tasks.length() &&
          (
            tasks[move_tasks[stage_cursor]].done ||
            tasks[move_tasks[stage_cursor]].staged
          ) {
      stage_cursor += 1
    }
    if stage_cursor == move_tasks.length() {
      dp_problem(
        diagnostics, "SCHEDULE_BLOCKED", "", "No legal sequence can complete the requested delivery.",
      )
      return Ok({
        status: "blocked",
        basis,
        operations: [],
        temporary_paths: [],
        diagnostics,
      })
    }
    let task = tasks[move_tasks[stage_cursor]]
    stage_cursor += 1
    let mut temporary = ".moonportcheck-stage-" + serial.to_string()
    while reserved_slots.contains(ascii_lower(temporary)) {
      serial += 1
      temporary = ".moonportcheck-stage-" + serial.to_string()
    }
    serial += 1
    reserved_slots[ascii_lower(temporary)] = true
    temporary_paths.push(temporary)
    let from = positions[task.origin.path]
    operations.push({
      kind: "move",
      source: spec.target.id,
      from,
      to: temporary,
      origin: task.origin,
    })
    slots.remove(ascii_lower(from))
    slots[ascii_lower(temporary)] = File
    positions[task.origin.path] = temporary
    task.staged = true
    dp_enqueue_watchers(ascii_lower(from), watchers, queue)
  }
  Ok({ status: "ready", basis, operations, temporary_paths, diagnostics, })
}
