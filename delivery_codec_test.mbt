///|
test "delivery_codec rejects malformed JSON and unknown spec fields" {
  match @moonportcheck.parse_delivery_spec("{") {
    Err(error) => assert_eq(error.code, "INPUT_JSON")
    Ok(_) => fail("Invalid JSON accepted")
  }
  match
    @moonportcheck.parse_delivery_spec(
      "{\"format\":\"moonportcheck-delivery-spec\",\"version\":1,\"extra\":true}",
    ) {
    Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
    Ok(_) => fail("Unknown field accepted")
  }
}

///|
test "delivery_codec strict plan round trip and required origin" {
  let text = "{\"format\":\"moonportcheck-delivery-plan\",\"version\":1,\"status\":\"ready\",\"basis\":\"{}\",\"operations\":[{\"kind\":\"copy\",\"source\":\"src\",\"from\":\"a\",\"to\":\"b\",\"origin\":{\"root\":\"src\",\"path\":\"a\"}}],\"temporary_paths\":[],\"diagnostics\":[]}"
  let plan = match @moonportcheck.parse_delivery_plan(text) {
    Ok(value) => value
    Err(error) => fail(error.message)
  }
  assert_eq(@moonportcheck.render_delivery_plan_json(plan), text)
  match
    @moonportcheck.parse_delivery_plan(
      text.replace(old="\"root\":\"src\",", new=""),
    ) {
    Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
    Ok(_) => fail("Missing origin root accepted")
  }
}

///|
fn dc_snapshot() -> @moonportcheck.Snapshot raise {
  match
    @moonportcheck.build_snapshot(
      [{ path: "文\"件", kind: @moonportcheck.File, }],
      [],
      [],
    ) {
    Ok(snapshot) => snapshot
    Err(error) => fail(error.message)
  }
}

///|
test "delivery_codec canonical basis ignores source and mapping ordering" {
  let snapshot = dc_snapshot()
  let a : @moonportcheck.DeliveryTree = { id: "a", snapshot, }
  let b : @moonportcheck.DeliveryTree = { id: "b", snapshot, }
  let first : @moonportcheck.DeliveryMapping = {
    mode: "copy",
    source: "a",
    from: "文\"件",
    to: "z",
  }
  let second : @moonportcheck.DeliveryMapping = {
    mode: "move",
    source: "target",
    from: "../semantic",
    to: "CON",
  }
  let one : @moonportcheck.DeliverySpec = {
    sources: [b, a],
    target: { id: "target", snapshot, },
    mappings: [second, first],
  }
  let two : @moonportcheck.DeliverySpec = {
    sources: [a, b],
    target: one.target,
    mappings: [first, second],
  }
  let canonical = @moonportcheck.render_delivery_spec_json(one)
  assert_eq(canonical, @moonportcheck.render_delivery_spec_json(two))
  let parsed = match @moonportcheck.parse_delivery_spec(canonical) {
    Ok(spec) => spec
    Err(error) => fail(error.message)
  }
  assert_eq(parsed.sources[0].id, "a")
  assert_eq(parsed.mappings[0].from, "文\"件")
  assert_eq(parsed.mappings[1].from, "../semantic")
  assert_eq(@moonportcheck.render_delivery_spec_json(parsed), canonical)
  // Parsing is structural; feasibility belongs to planner.
  let semantic = canonical.replace(
    old="\"mode\":\"copy\"",
    new="\"mode\":\"unknown\"",
  )
  match @moonportcheck.parse_delivery_spec(semantic) {
    Ok(_) => ()
    Err(error) => fail("Semantic issue incorrectly rejected: " + error.message)
  }
  for
    bad in [
      canonical.replace(old="\"version\":1", new="\"version\":2"),
      canonical.replace(old="\"id\":\"a\"", new="\"id\":\"a\",\"extra\":0"),
      canonical.replace(
        old="\"mode\":\"copy\"",
        new="\"mode\":\"copy\",\"extra\":0",
      ),
      canonical.replace(old="\"from\":\"../semantic\",", new=""),
      canonical.replace(
        old="\"sources\":[",
        new="\"sources\":{} ,\"discard\":[",
      ),
    ] {
    match @moonportcheck.parse_delivery_spec(bad) {
      Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
      Ok(_) => fail("Malformed spec accepted: " + bad)
    }
  }
}

///|
fn dc_plan_json() -> String {
  "{\"format\":\"moonportcheck-delivery-plan\",\"version\":1,\"status\":\"ready\",\"basis\":\"{}\",\"operations\":[{\"kind\":\"mkdir\",\"source\":\"\",\"from\":\"\",\"to\":\"dir\",\"origin\":{\"root\":\"\",\"path\":\"\"}}],\"temporary_paths\":[\"tmp\"],\"diagnostics\":[{\"code\":\"X\",\"path\":\"a\",\"message\":\"why\",\"step\":-1}]}"
}

///|
test "delivery_codec plan rejects all missing and wrongly typed mandatory fields" {
  let text = dc_plan_json()
  for
    bad in [
      "[]",
      text.replace(
        old="moonportcheck-delivery-plan",
        new="moonportcheck-delivery-spec",
      ),
      text.replace(old="\"version\":1", new="\"version\":1.5"),
      text.replace(old="\"status\":\"ready\"", new="\"status\":\"unknown\""),
      text.replace(old="\"basis\":\"{}\",", new=""),
      text.replace(old="\"basis\":\"{}\"", new="\"basis\":{}"),
      text.replace(old="\"kind\":\"mkdir\"", new="\"kind\":\"delete\""),
      text.replace(old="\"source\":\"\",", new=""),
      text.replace(old="\"from\":\"\",", new=""),
      text.replace(old="\"to\":\"dir\",", new=""),
      text.replace(
        old="\"origin\":{\"root\":\"\",\"path\":\"\"}",
        new="\"origin\":{}",
      ),
      text.replace(old="\"origin\":{", new="\"extra\":0,\"origin\":{"),
      text.replace(old="\"path\":\"\"", new="\"path\":\"\",\"extra\":0"),
      text.replace(
        old="\"temporary_paths\":[\"tmp\"]",
        new="\"temporary_paths\":[1]",
      ),
      text.replace(old="\"step\":-1", new="\"step\":1.5"),
      text.replace(old="\"step\":-1", new="\"step\":2147483648"),
      text.replace(old="\"code\":\"X\",", new=""),
      text.replace(old="\"step\":-1", new="\"step\":-1,\"extra\":0"),
    ] {
    match @moonportcheck.parse_delivery_plan(bad) {
      Err(error) => assert_eq(error.code, "INPUT_SCHEMA")
      Ok(_) => fail("Malformed plan accepted: " + bad)
    }
  }
  for status in ["ready", "blocked", "incomplete"] {
    let variant = text.replace(
      old="\"status\":\"ready\"",
      new="\"status\":\"" + status + "\"",
    )
    let plan = match @moonportcheck.parse_delivery_plan(variant) {
      Ok(plan) => plan
      Err(error) => fail(error.message)
    }
    assert_eq(@moonportcheck.render_delivery_plan_json(plan), variant)
    assert_true(@moonportcheck.render_delivery_plan_text(plan).contains(status))
    assert_true(
      @moonportcheck.render_delivery_plan_markdown(plan).contains("```json"),
    )
  }
}

///|
test "delivery_codec audit formats preserve identity trace and failure step" {
  let audit : @moonportcheck.DeliveryAudit = {
    status: "blocked",
    valid: false,
    first_failed_step: 2,
    diagnostics: [
      { code: "BAD", path: "文\"件", message: "failure\nreason", step: 2, },
    ],
    final_entries: [
      {
        path: "z",
        kind: @moonportcheck.File,
        origin: { root: "source", path: "original", },
      },
      {
        path: "a",
        kind: @moonportcheck.Directory,
        origin: { root: "", path: "", },
      },
    ],
    trace: [
      {
        step: 0,
        kind: "copy",
        from: "original",
        to: "z",
        origin: { root: "source", path: "original", },
      },
    ],
  }
  let text = @moonportcheck.render_delivery_audit_json(audit)
  let json = @json.parse(text) catch {
    _ => fail("Audit output is invalid JSON")
  }
  guard json is Object(fields) else { fail("Audit output is not an object") }
  assert_eq(
    fields.get("format"),
    Some("moonportcheck-delivery-audit".to_json()),
  )
  assert_eq(fields.get("version"), Some((1).to_json()))
  assert_eq(fields.get("first_failed_step"), Some((2).to_json()))
  assert_eq(fields.get("valid"), Some(false.to_json()))
  guard fields.get("final_entries") is Some(Array(entries)) else {
    fail("Missing entries")
  }
  guard entries[0] is Object(first) else { fail("Missing first entry") }
  assert_eq(first.get("path"), Some("a".to_json()))
  assert_true(@moonportcheck.render_delivery_audit_text(audit).contains("2"))
  assert_true(@moonportcheck.render_delivery_audit_text(audit).contains("BAD"))
  assert_true(
    @moonportcheck.render_delivery_audit_markdown(audit).contains("```json"),
  )
}
