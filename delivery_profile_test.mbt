///|
test "delivery fixed target profile is checked independently by planner and audit" {
  let text =
    #|{"format":"moonportcheck-delivery-spec","version":1,"sources":[],"target":{"id":"target","snapshot":{"format":"moonportcheck-snapshot","version":1,"profile":"other-profile","complete":true,"scope":[],"entries":[],"scan_issues":[]}},"mappings":[]}
  let spec = match @moonportcheck.parse_delivery_spec(text) {
    Ok(spec) => spec
    Err(_) => abort("Structurally valid snapshot rejected")
  }
  let planned = match @moonportcheck.plan_delivery(spec) {
    Ok(plan) => plan
    Err(_) => abort("Semantic rejection must use blocked plan")
  }
  assert_eq(planned.status, "blocked")
  let external : @moonportcheck.DeliveryPlan = {
    status: "ready",
    basis: @moonportcheck.render_delivery_spec_json(spec),
    operations: [],
    temporary_paths: [],
    diagnostics: [],
  }
  assert_false(@moonportcheck.audit_delivery_plan(spec, external).valid)
}
