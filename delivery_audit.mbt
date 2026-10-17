///| Independent replay auditor. The expected layout is derived from the spec;

///| no planner routines or plan-provided expected state participate.

///|
fn da_origin_key(origin : DeliveryOrigin) -> String {
  origin.root.to_json().stringify() + ":" + origin.path.to_json().stringify()
}

///|
fn da_parents(path : String) -> Array[String] {
  let parts = path.split("/").map(p => p.to_owned()).collect()
  let parents : Array[String] = []
  let mut prefix = ""
  for i in 0..<(parts.length() - 1) {
    prefix = if i == 0 { parts[i] } else { prefix + "/" + parts[i] }
    parents.push(prefix)
  }
  parents
}

///|
fn da_structure(path : String) -> Bool {
  if path == "" || path.has_prefix("/") || path.has_prefix("\\") {
    return false
  }
  let leading = path.iter().take(2).collect()
  if leading.length() == 2 &&
    leading[1] == ':' &&
    (
      (leading[0] >= 'A' && leading[0] <= 'Z') ||
      (leading[0] >= 'a' && leading[0] <= 'z')
    ) {
    return false
  }
  for c in path.iter() {
    if c == '\\' || c.to_int() == 0 {
      return false
    }
  }
  for p in path.split("/") {
    if p == "" || p == "." || p == ".." {
      return false
    }
  }
  true
}

///|
fn da_portable(path : String) -> Bool {
  let diagnostics : Array[Diagnostic] = []
  ignore(check_path(path, 1, diagnostics))
  diagnostics.is_empty()
}

///|
fn da_entries(
  state : Map[String, DeliveryStateEntry],
) -> Array[DeliveryStateEntry] {
  let result : Array[DeliveryStateEntry] = []
  for key in sorted_keys(state) {
    result.push(state[key])
  }
  result.sort_by((a, b) => ordinal_compare(a.path, b.path))
  result
}

///|
fn da_reject(
  code : String,
  path : String,
  message : String,
  step : Int,
  state : Map[String, DeliveryStateEntry],
  trace : Array[DeliveryTrace],
) -> DeliveryAudit {
  {
    status: if code == "SNAPSHOT_INCOMPLETE" {
      "incomplete"
    } else {
      "invalid"
    },
    valid: false,
    first_failed_step: step,
    diagnostics: [{ code, path, message, step, }],
    final_entries: da_entries(state),
    trace,
  }
}

///|
fn da_empty_origin() -> DeliveryOrigin {
  { root: "", path: "", }
}

///|
pub fn audit_delivery_plan(
  spec : DeliverySpec,
  plan : DeliveryPlan,
) -> DeliveryAudit {
  let state : Map[String, DeliveryStateEntry] = Map([])
  let trace : Array[DeliveryTrace] = []
  let roots : Map[String, Map[String, DeliveryStateEntry]] = Map([])
  let children_by_root : Map[String, Map[String, Array[DeliveryStateEntry]]] = Map([],
  )
  let all = spec.sources.copy()
  all.push(spec.target)
  for tree in all {
    if tree.id == "" || roots.contains(tree.id) {
      return da_reject(
        "ROOT_ID",
        tree.id,
        "Root IDs must be nonempty and unique.",
        -1,
        state,
        trace,
      )
    }
    if !tree.snapshot.complete ||
      !tree.snapshot.scan_issues.is_empty() ||
      !tree.snapshot.scope.is_empty() {
      return da_reject(
        "SNAPSHOT_INCOMPLETE",
        tree.id,
        "Every root requires a complete, unscoped snapshot without scan issues.",
        -1,
        state,
        trace,
      )
    }
    if tree.id == spec.target.id &&
      tree.snapshot.profile != "portable-windows-v1" {
      return da_reject(
        "TARGET_PROFILE_UNSUPPORTED",
        tree.id,
        "Delivery targets require portable-windows-v1.",
        -1,
        state,
        trace,
      )
    }
    let entries : Map[String, DeliveryStateEntry] = Map([])
    let explicit : Map[String, Bool] = Map([])
    for entry in tree.snapshot.entries {
      if !da_structure(entry.path) || explicit.contains(entry.path) {
        return da_reject(
          "SOURCE_STRUCTURE",
          entry.path,
          "Snapshot entries must have unique, structurally valid relative paths.",
          -1,
          state,
          trace,
        )
      }
      explicit[entry.path] = true
      match entries.get(entry.path) {
        Some(old) if old.kind != entry.kind =>
          return da_reject(
            "SOURCE_STRUCTURE",
            entry.path,
            "A source file cannot also be a directory.",
            -1,
            state,
            trace,
          )
        _ => ()
      }
      entries[entry.path] = {
        path: entry.path,
        kind: entry.kind,
        origin: if entry.kind == File {
          { root: tree.id, path: entry.path, }
        } else {
          da_empty_origin()
        },
      }
      for parent in da_parents(entry.path) {
        match entries.get(parent) {
          Some(old) if old.kind == File =>
            return da_reject(
              "SOURCE_STRUCTURE", parent, "A source file cannot be an ancestor.",
              -1, state, trace,
            )
          _ =>
            entries[parent] = {
              path: parent,
              kind: Directory,
              origin: da_empty_origin(),
            }
        }
      }
    }
    roots[tree.id] = entries
    let children : Map[String, Array[DeliveryStateEntry]] = Map([])
    for entry in entries.values() {
      let parent = match entry.path.rev_split_once("/") {
        Some((prefix, _)) => prefix.to_owned()
        None => ""
      }
      match children.get(parent) {
        Some(items) => items.push(entry)
        None => children[parent] = [entry]
      }
    }
    children_by_root[tree.id] = children
  }
  if !audit(spec.target.snapshot.entries).diagnostics.is_empty() {
    return da_reject(
      "TARGET_UNREPRESENTABLE", "", "Initial target tree is not portable under ASCII case folding.",
      -1, state, trace,
    )
  }
  let initial = roots[spec.target.id]
  let expected : Map[String, DeliveryStateEntry] = Map([])
  for entry in initial.values() {
    let slot = ascii_lower(entry.path)
    state[slot] = entry
    expected[slot] = entry
  }
  let intents : Map[String, DeliveryIntent] = Map([])
  let move_goals : Map[String, String] = Map([])
  let directory_goals : Map[String, DeliveryStateEntry] = Map([])
  // Expand each mapping from initial source identities, never from replay state.
  for mapping in spec.mappings {
    if mapping.mode != "copy" && mapping.mode != "move" {
      return da_reject(
        "MAPPING_MODE",
        mapping.to,
        "Mapping mode must be copy or move.",
        -1,
        state,
        trace,
      )
    }
    guard roots.get(mapping.source) is Some(source) else {
      return da_reject(
        "MAPPING_SOURCE",
        mapping.from,
        "Mapping references an unknown source root.",
        -1,
        state,
        trace,
      )
    }
    if (mapping.to != "" && !da_portable(mapping.to)) ||
      (mapping.from != "" && !da_structure(mapping.from)) {
      return da_reject(
        "MAPPING_PATH",
        mapping.to,
        "Mapping paths are not structurally valid or the destination is not portable.",
        -1,
        state,
        trace,
      )
    }
    let source_kind = if mapping.from == "" {
      Some(Directory)
    } else {
      source.get(mapping.from).map(e => e.kind)
    }
    guard source_kind is Some(kind) else {
      return da_reject(
        "MAPPING_SOURCE",
        mapping.from,
        "Mapping source does not exist with exact spelling in the initial snapshot.",
        -1,
        state,
        trace,
      )
    }
    if mapping.mode == "move" &&
      (mapping.source != spec.target.id || kind != File) {
      return da_reject(
        "MAPPING_MOVE",
        mapping.from,
        "Move requires an initial target file; external roots and directories are read only.",
        -1,
        state,
        trace,
      )
    }
    let expanded : Array[(DeliveryStateEntry, String)] = []
    if kind == File {
      expanded.push((source[mapping.from], mapping.to))
    } else {
      if mapping.to != "" {
        match directory_goals.get(ascii_lower(mapping.to)) {
          Some(old) if old.path != mapping.to =>
            return da_reject(
              "TARGET_UNREPRESENTABLE",
              mapping.to,
              "Mapped directories have inconsistent ASCII casing.",
              -1,
              state,
              trace,
            )
          _ => ()
        }
        directory_goals[ascii_lower(mapping.to)] = {
          path: mapping.to,
          kind: Directory,
          origin: da_empty_origin(),
        }
      }
      let prefix = if mapping.from == "" { "" } else { mapping.from + "/" }
      let queue : Array[String] = [mapping.from]
      let children = children_by_root[mapping.source]
      let mut cursor = 0
      while cursor < queue.length() {
        let directory = queue[cursor]
        cursor = cursor + 1
        match children.get(directory) {
          Some(items) =>
            for entry in items {
              let relative = entry.path[prefix.length():].to_owned()
              expanded.push(
                (
                  entry,
                  if mapping.to == "" {
                    relative
                  } else {
                    mapping.to + "/" + relative
                  },
                ),
              )
              if entry.kind == Directory {
                queue.push(entry.path)
              }
            }
          None => ()
        }
      }
    }
    for pair in expanded {
      let (entry, destination) = pair
      if !da_portable(destination) {
        return da_reject(
          "TARGET_UNREPRESENTABLE", destination, "Expanded destination is not portable.",
          -1, state, trace,
        )
      }
      let slot = ascii_lower(destination)
      if entry.kind == Directory {
        match directory_goals.get(slot) {
          Some(old) if old.path != destination =>
            return da_reject(
              "TARGET_UNREPRESENTABLE", destination, "Destination directories have inconsistent ASCII casing.",
              -1, state, trace,
            )
          _ => ()
        }
        directory_goals[slot] = {
          path: destination,
          kind: Directory,
          origin: da_empty_origin(),
        }
      } else {
        if intents.contains(slot) {
          return da_reject(
            "MAPPING_COLLISION", destination, "Multiple file intents occupy the same destination slot.",
            -1, state, trace,
          )
        }
        intents[slot] = {
          mode: mapping.mode,
          source: mapping.source,
          from: entry.path,
          to: destination,
          origin: entry.origin,
        }
        if mapping.mode == "move" {
          let identity = da_origin_key(entry.origin)
          if move_goals.contains(identity) {
            return da_reject(
              "MAPPING_MOVE",
              entry.path,
              "Each initial target file can have at most one Move intent.",
              -1,
              state,
              trace,
            )
          }
          move_goals[identity] = slot
        }
      }
    }
  }
  // Remove every Move origin before adding goals, so files may become directories.
  for intent in intents.values() {
    if intent.mode == "move" {
      expected.remove(ascii_lower(intent.from))
    }
  }
  for intent in intents.values() {
    let slot = ascii_lower(intent.to)
    if expected.contains(slot) {
      return da_reject(
        "MAPPING_OCCUPIED",
        intent.to,
        "Destination is occupied by an initial entry without a vacating Move.",
        -1,
        state,
        trace,
      )
    }
    expected[slot] = { path: intent.to, kind: File, origin: intent.origin, }
    for parent in da_parents(intent.to) {
      match directory_goals.get(ascii_lower(parent)) {
        Some(old) if old.path != parent =>
          return da_reject(
            "TARGET_UNREPRESENTABLE", parent, "expected directory casing is inconsistent.",
            -1, state, trace,
          )
        _ =>
          directory_goals[ascii_lower(parent)] = {
            path: parent,
            kind: Directory,
            origin: da_empty_origin(),
          }
      }
    }
  }
  let extra_directories = directory_goals.values().collect()
  for entry in extra_directories {
    for parent in da_parents(entry.path) {
      match directory_goals.get(ascii_lower(parent)) {
        Some(old) if old.path != parent =>
          return da_reject(
            "TARGET_UNREPRESENTABLE", parent, "expected directory casing is inconsistent.",
            -1, state, trace,
          )
        _ =>
          directory_goals[ascii_lower(parent)] = {
            path: parent,
            kind: Directory,
            origin: da_empty_origin(),
          }
      }
    }
  }
  for entry in directory_goals.values() {
    let slot = ascii_lower(entry.path)
    match expected.get(slot) {
      Some(old) if old.kind != Directory || old.path != entry.path =>
        return da_reject(
          "TARGET_UNREPRESENTABLE",
          entry.path,
          "A expected directory collides with a file or a differently cased directory.",
          -1,
          state,
          trace,
        )
      _ => expected[slot] = entry
    }
  }
  let final_paths : Array[PathEntry] = da_entries(expected).map(e => {
    path: e.path,
    kind: e.kind,
  })
  if !audit(final_paths).diagnostics.is_empty() {
    return da_reject(
      "TARGET_UNREPRESENTABLE", "", "expected target tree contains incompatible path prefixes.",
      -1, state, trace,
    )
  }
  if plan.status != "ready" || !plan.diagnostics.is_empty() {
    return da_reject(
      "PLAN_NOT_READY", "", "Only a ready plan without blocking diagnostics can be audited as acceptable.",
      -1, state, trace,
    )
  }
  if plan.basis != render_delivery_spec_json(spec) {
    return da_reject(
      "BASIS_MISMATCH", "", "Plan basis must exactly match the canonical input spec.",
      -1, state, trace,
    )
  }
  let temps : Map[String, Bool] = Map([])
  for path in plan.temporary_paths {
    let slot = ascii_lower(path)
    if !da_portable(path) ||
      path.contains("/") ||
      temps.contains(slot) ||
      state.contains(slot) ||
      expected.contains(slot) {
      return da_reject(
        "TEMPORARY_CONFLICT", path, "Temporary paths must be unique portable root-level slots absent from initial and expected trees.",
        -1, state, trace,
      )
    }
    temps[slot] = true
  }
  for step, op in plan.operations {
    let slot = ascii_lower(op.to)
    if !da_portable(op.to) {
      return da_reject(
        "OP_PATH",
        op.to,
        "Operation destination is not portable.",
        step,
        state,
        trace,
      )
    }
    if state.contains(slot) {
      return da_reject(
        "DESTINATION_OCCUPIED",
        op.to,
        "Operation destination is already occupied.",
        step,
        state,
        trace,
      )
    }
    for parent in da_parents(op.to) {
      match state.get(ascii_lower(parent)) {
        Some(e) if e.kind == Directory && e.path == parent => ()
        _ =>
          return da_reject(
            "PARENT_MISSING", parent, "Operation requires an existing directory with correct casing.",
            step, state, trace,
          )
      }
    }
    if op.kind == "mkdir" {
      if op.source != "" || op.from != "" || op.origin != da_empty_origin() {
        return da_reject(
          "MKDIR_FIELDS",
          op.to,
          "Mkdir must have empty source, from and origin fields.",
          step,
          state,
          trace,
        )
      }
      match expected.get(slot) {
        Some(e) if e.kind == Directory && e.path == op.to => state[slot] = e
        _ =>
          return da_reject(
            "UNRELATED_MKDIR",
            op.to,
            "Mkdir is not required by the expected layout.",
            step,
            state,
            trace,
          )
      }
    } else {
      if op.kind != "copy" && op.kind != "move" {
        return da_reject(
          "OP_KIND",
          op.to,
          "Operation kind must be mkdir, copy or move.",
          step,
          state,
          trace,
        )
      }
      let actual = if op.source == spec.target.id {
        state.get(ascii_lower(op.from))
      } else {
        match roots.get(op.source) {
          Some(tree) => tree.get(op.from)
          None => None
        }
      }
      guard actual is Some(entry) &&
        entry.kind == File &&
        entry.path == op.from &&
        entry.origin == op.origin else {
        return da_reject(
          "SOURCE_IDENTITY",
          op.from,
          "Source must currently hold the exact claimed initial file identity.",
          step,
          state,
          trace,
        )
      }
      if op.kind == "copy" {
        match intents.get(slot) {
          Some(intent) if intent.mode == "copy" &&
            intent.origin == op.origin &&
            intent.to == op.to => ()
          _ =>
            return da_reject(
              "UNRELATED_COPY",
              op.to,
              "Copy must deliver a declared Copy identity to its exact destination.",
              step,
              state,
              trace,
            )
        }
      } else {
        if op.source != spec.target.id {
          return da_reject(
            "READONLY_SOURCE",
            op.from,
            "External source roots cannot be changed by Move.",
            step,
            state,
            trace,
          )
        }
        guard move_goals.get(da_origin_key(op.origin)) is Some(goal) else {
          return da_reject(
            "UNRELATED_MOVE",
            op.from,
            "Move identity has no declared target Move intent.",
            step,
            state,
            trace,
          )
        }
        if !temps.contains(slot) &&
          (slot != goal || expected[goal].path != op.to) {
          return da_reject(
            "UNRELATED_MOVE",
            op.to,
            "Move destination must be its declared expected goal or a declared temporary slot.",
            step,
            state,
            trace,
          )
        }
        state.remove(ascii_lower(op.from))
      }
      state[slot] = { path: op.to, kind: File, origin: op.origin, }
    }
    trace.push({
      step,
      kind: op.kind,
      from: op.from,
      to: op.to,
      origin: op.origin,
    })
  }
  for slot in temps.keys() {
    if state.contains(slot) {
      return da_reject(
        "TEMPORARY_LEFTOVER",
        state[slot].path,
        "Temporary file remains after replay.",
        -1,
        state,
        trace,
      )
    }
  }
  if state.length() != expected.length() {
    return da_reject(
      "FINAL_LAYOUT", "", "expected entry count differs from the independently derived target layout.",
      -1, state, trace,
    )
  }
  for slot, expected in expected {
    if state.get(slot) != Some(expected) {
      return da_reject(
        "FINAL_IDENTITY",
        expected.path,
        "expected path, kind or initial file identity differs from the independently derived target layout.",
        -1,
        state,
        trace,
      )
    }
  }
  {
    status: "valid",
    valid: true,
    first_failed_step: -1,
    diagnostics: [],
    final_entries: da_entries(state),
    trace,
  }
}
