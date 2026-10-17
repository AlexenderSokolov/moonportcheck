///|
fn delivery_schema(message : String) -> InputError {
  { code: "INPUT_SCHEMA", message, }
}

///|
fn delivery_document(
  text : String,
  format : String,
  allowed : Array[String],
) -> Result[Map[String, Json], InputError] {
  let value = @json.parse(text) catch {
    _ => return Err({ code: "INPUT_JSON", message: "Invalid delivery JSON.", })
  }
  guard value is Object(fields) else {
    return Err(delivery_schema("Delivery document must be an object."))
  }
  match reject_unknown_fields(fields, allowed) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard fields.get("format") is Some(String(found)) && found == format else {
    return Err(delivery_schema("Unsupported delivery format."))
  }
  guard fields.get("version") is Some(Number(version, ..)) && version == 1.0 else {
    return Err(delivery_schema("Unsupported delivery version."))
  }
  Ok(fields)
}

///|
fn delivery_tree(value : Json) -> Result[DeliveryTree, InputError] {
  guard value is Object(fields) else {
    return Err(delivery_schema("Delivery root must be an object."))
  }
  match reject_unknown_fields(fields, ["id", "snapshot"]) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard fields.get("id") is Some(String(id)) else {
    return Err(delivery_schema("Delivery root requires a string id."))
  }
  guard fields.get("snapshot") is Some(snapshot) && snapshot is Object(_) else {
    return Err(delivery_schema("Delivery root requires a snapshot object."))
  }
  let snapshot = match parse_snapshot(snapshot.stringify()) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({ id, snapshot, })
}

///|
/// Parse structure only; path, namespace and mapping feasibility belong to planning.
pub fn parse_delivery_spec(text : String) -> Result[DeliverySpec, InputError] {
  let fields = match
    delivery_document(text, "moonportcheck-delivery-spec", [
      "format", "version", "sources", "target", "mappings",
    ]) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  guard fields.get("sources") is Some(Array(items)) else {
    return Err(delivery_schema("Delivery spec requires sources array."))
  }
  let sources : Array[DeliveryTree] = []
  for item in items {
    match delivery_tree(item) {
      Err(error) => return Err(error)
      Ok(tree) => sources.push(tree)
    }
  }
  guard fields.get("target") is Some(target) else {
    return Err(delivery_schema("Delivery spec requires target."))
  }
  let target = match delivery_tree(target) {
    Err(error) => return Err(error)
    Ok(tree) => tree
  }
  guard fields.get("mappings") is Some(Array(items)) else {
    return Err(delivery_schema("Delivery spec requires mappings array."))
  }
  let mappings : Array[DeliveryMapping] = []
  for item in items {
    guard item is Object(fields) else {
      return Err(delivery_schema("Mapping must be an object."))
    }
    match reject_unknown_fields(fields, ["mode", "source", "from", "to"]) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    guard fields.get("mode") is Some(String(mode)) else {
      return Err(delivery_schema("Mapping requires string mode."))
    }
    guard fields.get("source") is Some(String(source)) else {
      return Err(delivery_schema("Mapping requires string source."))
    }
    guard fields.get("from") is Some(String(from)) else {
      return Err(delivery_schema("Mapping requires string from."))
    }
    guard fields.get("to") is Some(String(to)) else {
      return Err(delivery_schema("Mapping requires string to."))
    }
    mappings.push({ mode, source, from, to, })
  }
  Ok({ sources, target, mappings, })
}

///|
fn delivery_origin(value : Json) -> Result[DeliveryOrigin, InputError] {
  guard value is Object(fields) else {
    return Err(delivery_schema("Origin must be an object."))
  }
  match reject_unknown_fields(fields, ["root", "path"]) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  guard fields.get("root") is Some(String(root)) else {
    return Err(delivery_schema("Origin requires string root."))
  }
  guard fields.get("path") is Some(String(path)) else {
    return Err(delivery_schema("Origin requires string path."))
  }
  Ok({ root, path, })
}

///|
fn delivery_diagnostics(
  items : Array[Json],
) -> Result[Array[DeliveryDiagnostic], InputError] {
  let diagnostics : Array[DeliveryDiagnostic] = []
  for item in items {
    guard item is Object(fields) else {
      return Err(delivery_schema("Diagnostic must be an object."))
    }
    match reject_unknown_fields(fields, ["code", "path", "message", "step"]) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    guard fields.get("code") is Some(String(code)) else {
      return Err(delivery_schema("Diagnostic requires string code."))
    }
    guard fields.get("path") is Some(String(path)) else {
      return Err(delivery_schema("Diagnostic requires string path."))
    }
    guard fields.get("message") is Some(String(message)) else {
      return Err(delivery_schema("Diagnostic requires string message."))
    }
    let step = match parse_int_field(fields, "step") {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    diagnostics.push({ code, path, message, step, })
  }
  Ok(diagnostics)
}

///|
/// Strict external plan parser. Operation sequencing and identity are audited separately.
pub fn parse_delivery_plan(text : String) -> Result[DeliveryPlan, InputError] {
  let fields = match
    delivery_document(text, "moonportcheck-delivery-plan", [
      "format", "version", "status", "basis", "operations", "temporary_paths", "diagnostics",
    ]) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  guard fields.get("status") is Some(String(status)) else {
    return Err(delivery_schema("Plan requires string status."))
  }
  if !["ready", "blocked", "incomplete"].contains(status) {
    return Err(delivery_schema("Unknown plan status."))
  }
  guard fields.get("basis") is Some(String(basis)) else {
    return Err(delivery_schema("Plan requires string basis."))
  }
  guard fields.get("operations") is Some(Array(items)) else {
    return Err(delivery_schema("Plan requires operations array."))
  }
  let operations : Array[DeliveryOperation] = []
  for item in items {
    guard item is Object(fields) else {
      return Err(delivery_schema("Operation must be an object."))
    }
    match
      reject_unknown_fields(fields, ["kind", "source", "from", "to", "origin"]) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    guard fields.get("kind") is Some(String(kind)) else {
      return Err(delivery_schema("Operation requires string kind."))
    }
    if !["mkdir", "copy", "move"].contains(kind) {
      return Err(delivery_schema("Unknown operation kind."))
    }
    guard fields.get("source") is Some(String(source)) else {
      return Err(delivery_schema("Operation requires string source."))
    }
    guard fields.get("from") is Some(String(from)) else {
      return Err(delivery_schema("Operation requires string from."))
    }
    guard fields.get("to") is Some(String(to)) else {
      return Err(delivery_schema("Operation requires string to."))
    }
    guard fields.get("origin") is Some(value) else {
      return Err(delivery_schema("Operation requires origin."))
    }
    let origin = match delivery_origin(value) {
      Err(error) => return Err(error)
      Ok(origin) => origin
    }
    operations.push({ kind, source, from, to, origin, })
  }
  guard fields.get("temporary_paths") is Some(Array(items)) else {
    return Err(delivery_schema("Plan requires temporary_paths array."))
  }
  let temporary_paths = match
    parse_diagnostic_strings(items, "temporary_paths") {
    Err(error) => return Err(error)
    Ok(values) => values
  }
  guard fields.get("diagnostics") is Some(Array(items)) else {
    return Err(delivery_schema("Plan requires diagnostics array."))
  }
  let diagnostics = match delivery_diagnostics(items) {
    Err(error) => return Err(error)
    Ok(values) => values
  }
  Ok({ status, basis, operations, temporary_paths, diagnostics, })
}

///|
fn delivery_tree_json(tree : DeliveryTree) -> String {
  "{\"id\":" +
  quote(tree.id) +
  ",\"snapshot\":" +
  render_snapshot_json(tree.snapshot) +
  "}"
}

///|
fn delivery_mapping_order(a : DeliveryMapping, b : DeliveryMapping) -> Int {
  for
    pair in [
      (a.mode, b.mode),
      (a.source, b.source),
      (a.from, b.from),
      (a.to, b.to),
    ] {
    let order = ordinal_compare(pair.0, pair.1)
    if order != 0 {
      return order
    }
  }
  0
}

///|
/// Canonical expanded spec content used as a plan's basis; caller order is irrelevant.
pub fn render_delivery_spec_json(spec : DeliverySpec) -> String {
  let sources = spec.sources.copy()
  sources.sort_by((a, b) => {
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
  let mappings = spec.mappings.copy()
  mappings.sort_by(delivery_mapping_order)
  "{\"format\":\"moonportcheck-delivery-spec\",\"version\":1,\"sources\":[" +
  sources.map(delivery_tree_json).join(",") +
  "],\"target\":" +
  delivery_tree_json(spec.target) +
  ",\"mappings\":[" +
  mappings
  .map(mapping => {
    "{\"mode\":" +
    quote(mapping.mode) +
    ",\"source\":" +
    quote(mapping.source) +
    ",\"from\":" +
    quote(mapping.from) +
    ",\"to\":" +
    quote(mapping.to) +
    "}"
  })
  .join(",") +
  "]}"
}

///|
fn delivery_origin_json(origin : DeliveryOrigin) -> String {
  "{\"root\":" + quote(origin.root) + ",\"path\":" + quote(origin.path) + "}"
}

///|
fn delivery_diagnostics_json(diagnostics : Array[DeliveryDiagnostic]) -> String {
  "[" +
  diagnostics
  .map(d => {
    "{\"code\":" +
    quote(d.code) +
    ",\"path\":" +
    quote(d.path) +
    ",\"message\":" +
    quote(d.message) +
    ",\"step\":" +
    d.step.to_string() +
    "}"
  })
  .join(",") +
  "]"
}

///|
pub fn render_delivery_plan_json(plan : DeliveryPlan) -> String {
  "{\"format\":\"moonportcheck-delivery-plan\",\"version\":1,\"status\":" +
  quote(plan.status) +
  ",\"basis\":" +
  quote(plan.basis) +
  ",\"operations\":[" +
  plan.operations
  .map(op => {
    "{\"kind\":" +
    quote(op.kind) +
    ",\"source\":" +
    quote(op.source) +
    ",\"from\":" +
    quote(op.from) +
    ",\"to\":" +
    quote(op.to) +
    ",\"origin\":" +
    delivery_origin_json(op.origin) +
    "}"
  })
  .join(",") +
  "],\"temporary_paths\":" +
  json_strings(plan.temporary_paths) +
  ",\"diagnostics\":" +
  delivery_diagnostics_json(plan.diagnostics) +
  "}"
}

///|
pub fn render_delivery_audit_json(audit : DeliveryAudit) -> String {
  let entries = audit.final_entries.copy()
  entries.sort_by((a, b) => ordinal_compare(a.path, b.path))
  "{\"format\":\"moonportcheck-delivery-audit\",\"version\":1,\"status\":" +
  quote(audit.status) +
  ",\"valid\":" +
  audit.valid.to_string() +
  ",\"first_failed_step\":" +
  audit.first_failed_step.to_string() +
  ",\"diagnostics\":" +
  delivery_diagnostics_json(audit.diagnostics) +
  ",\"final_entries\":[" +
  entries
  .map(entry => {
    "{\"path\":" +
    quote(entry.path) +
    ",\"kind\":" +
    quote(source_kind_name(entry.kind)) +
    ",\"origin\":" +
    delivery_origin_json(entry.origin) +
    "}"
  })
  .join(",") +
  "],\"trace\":[" +
  audit.trace
  .map(trace => {
    "{\"step\":" +
    trace.step.to_string() +
    ",\"kind\":" +
    quote(trace.kind) +
    ",\"from\":" +
    quote(trace.from) +
    ",\"to\":" +
    quote(trace.to) +
    ",\"origin\":" +
    delivery_origin_json(trace.origin) +
    "}"
  })
  .join(",") +
  "]}"
}

///|
pub fn render_delivery_plan_text(plan : DeliveryPlan) -> String {
  let lines = [
    "Delivery plan: " + plan.status,
    "Operations: " + plan.operations.length().to_string(),
  ]
  for step, op in plan.operations {
    lines.push(
      step.to_string() +
      ": " +
      op.kind +
      " " +
      quote(op.source) +
      ":" +
      quote(op.from) +
      " -> " +
      quote(op.to),
    )
  }
  for d in plan.diagnostics {
    lines.push(
      d.code +
      " at " +
      quote(d.path) +
      " (step " +
      d.step.to_string() +
      "): " +
      d.message,
    )
  }
  lines.join("\n") + "\n"
}

///|
pub fn render_delivery_plan_markdown(plan : DeliveryPlan) -> String {
  "# Delivery plan\n\nStatus: " +
  plan.status +
  "\n\nOperations: " +
  plan.operations.length().to_string() +
  "\n\n```json\n" +
  render_delivery_plan_json(plan) +
  "\n```\n"
}

///|
pub fn render_delivery_audit_text(audit : DeliveryAudit) -> String {
  let lines = [
    "Delivery audit: " + audit.status,
    "Valid: " + audit.valid.to_string(),
    "First failed step: " + audit.first_failed_step.to_string(),
  ]
  for trace in audit.trace {
    lines.push(
      trace.step.to_string() +
      ": " +
      trace.kind +
      " " +
      quote(trace.from) +
      " -> " +
      quote(trace.to),
    )
  }
  for d in audit.diagnostics {
    lines.push(
      d.code +
      " at " +
      quote(d.path) +
      " (step " +
      d.step.to_string() +
      "): " +
      d.message,
    )
  }
  lines.join("\n") + "\n"
}

///|
pub fn render_delivery_audit_markdown(audit : DeliveryAudit) -> String {
  "# Delivery audit\n\nStatus: " +
  audit.status +
  "\n\nValid: " +
  audit.valid.to_string() +
  "\n\nFirst failed step: " +
  audit.first_failed_step.to_string() +
  "\n\n```json\n" +
  render_delivery_audit_json(audit) +
  "\n```\n"
}
