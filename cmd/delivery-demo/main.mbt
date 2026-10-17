///|
/// A pure-library consumer: fixed logical snapshots, no filesystem or host APIs.
fn demo_spec(
  entries : String,
  mappings : String,
) -> @moonportcheck.DeliverySpec {
  let text = "{\"format\":\"moonportcheck-delivery-spec\",\"version\":1,\"sources\":[],\"target\":{\"id\":\"target\",\"snapshot\":{\"format\":\"moonportcheck-snapshot\",\"version\":1,\"profile\":\"portable-windows-v1\",\"complete\":true,\"scope\":[],\"entries\":[" +
    entries +
    "],\"scan_issues\":[]}},\"mappings\":[" +
    mappings +
    "]}"
  match @moonportcheck.parse_delivery_spec(text) {
    Ok(spec) => spec
    Err(error) => abort("Demo spec failed: " + error.message)
  }
}

///|
fn demo_case(
  spec : @moonportcheck.DeliverySpec,
  expected : Array[(String, String, String)],
) -> Unit {
  let plan = match @moonportcheck.plan_delivery(spec) {
    Ok(plan) => plan
    Err(error) => abort("Demo planning failed: " + error.message)
  }
  if plan.status != "ready" {
    abort("Demo plan was not ready")
  }
  let audit = @moonportcheck.audit_delivery_plan(spec, plan)
  if !audit.valid {
    abort(
      "Demo audit failed: " + @moonportcheck.render_delivery_audit_json(audit),
    )
  }
  if audit.final_entries.length() != expected.length() {
    abort("Demo final entry count differs")
  }
  for entry in expected {
    if !audit.final_entries.any(actual => {
        actual.path == entry.0 &&
        actual.origin.root == entry.1 &&
        actual.origin.path == entry.2
      }) {
      abort("Demo final identity differs at " + entry.0)
    }
  }
  println(@moonportcheck.render_delivery_plan_json(plan))
  println(@moonportcheck.render_delivery_audit_json(audit))
}

///|
fn main {
  // Copy reads the initial b identity even after moves relocate it to c.
  demo_case(
    demo_spec(
      "{\"path\":\"a\",\"kind\":\"file\"},{\"path\":\"b\",\"kind\":\"file\"}", "{\"mode\":\"move\",\"source\":\"target\",\"from\":\"b\",\"to\":\"c\"},{\"mode\":\"move\",\"source\":\"target\",\"from\":\"a\",\"to\":\"b\"},{\"mode\":\"copy\",\"source\":\"target\",\"from\":\"b\",\"to\":\"d\"}",
    ),
    [("b", "target", "a"), ("c", "target", "b"), ("d", "target", "b")],
  )
  // A swap needs temporary storage to satisfy both occupied destinations.
  demo_case(
    demo_spec(
      "{\"path\":\"a\",\"kind\":\"file\"},{\"path\":\"b\",\"kind\":\"file\"}", "{\"mode\":\"move\",\"source\":\"target\",\"from\":\"a\",\"to\":\"b\"},{\"mode\":\"move\",\"source\":\"target\",\"from\":\"b\",\"to\":\"a\"}",
    ),
    [("a", "target", "b"), ("b", "target", "a")],
  )
  // Vacate p before mkdir p, then copy p's original identity into p/child.
  demo_case(
    demo_spec(
      "{\"path\":\"p\",\"kind\":\"file\"}", "{\"mode\":\"move\",\"source\":\"target\",\"from\":\"p\",\"to\":\"archive\"},{\"mode\":\"copy\",\"source\":\"target\",\"from\":\"p\",\"to\":\"p/child\"}",
    ),
    [("archive", "target", "p"), ("p", "", ""), ("p/child", "target", "p")],
  )
}
