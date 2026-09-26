///|
test "catalog contains every v1 rule and scan issue in stable code order" {
  let catalog = @moonportcheck.rules()
  @test.assert_eq(catalog.map(rule => rule.code), [
    "NAME_INVALID_CHAR", "NAME_RESERVED", "NAME_TRAILING_DOT_SPACE", "PATH_ABSOLUTE",
    "PATH_CASE_COLLISION", "PATH_DOT_COMPONENT", "PATH_DRIVE", "PATH_DUPLICATE",
    "PATH_EMPTY", "PATH_EMPTY_COMPONENT", "PATH_KIND_CONFLICT", "SCAN_IO_ERROR",
    "SCAN_LINK_SKIPPED", "SCAN_NAME_ENCODING", "SCAN_TYPE_UNSUPPORTED",
  ])
  for rule in catalog {
    assert_true(rule.title.length() > 0)
    assert_true(rule.reason.length() > 0)
    assert_true(rule.examples.length() > 0)
    assert_true(rule.suggestion.length() > 0)
    @test.assert_eq(@moonportcheck.explain(rule.code), Some(rule))
  }
}

///|
test "rule lookup is exact and unknown codes stay unknown" {
  assert_true(@moonportcheck.explain("NAME_RESERVED") is Some(_))
  @test.assert_eq(@moonportcheck.explain("name_reserved"), None)
  @test.assert_eq(@moonportcheck.explain(" NAME_RESERVED"), None)
  @test.assert_eq(@moonportcheck.explain("UNKNOWN_RULE"), None)
  @test.assert_eq(@moonportcheck.explain(""), None)
}

///|
test "catalog path examples actually trigger their existing v1 rule" {
  let catalog = @moonportcheck.rules()
  assert_eq(catalog.length(), 15)
  for rule in catalog {
    if !rule.code.has_prefix("SCAN_") {
      let report = @moonportcheck.audit(files(rule.examples))
      assert_true(
        report.diagnostics.any(diagnostic => diagnostic.code == rule.code),
      )
    }
  }
}

///|
test "rule JSON is parseable complete deterministic and does not reorder caller data" {
  let catalog = @moonportcheck.rules()
  let reversed = catalog.rev()
  let saved = reversed.copy()
  let normal = @moonportcheck.render_rules_json(catalog)
  assert_eq(normal, @moonportcheck.render_rules_json(reversed))
  @test.assert_eq(reversed, saved)
  let parsed = @json.parse(normal) catch {
    _ => fail("Catalog must be valid JSON")
  }
  guard parsed is Array(items) else { fail("Catalog JSON must be an array") }
  assert_eq(items.length(), 15)
  guard items[0] is Object(fields) else { fail("Rule must be an object") }
  assert_eq(fields.length(), 5)
  @test.assert_eq(fields.get("code"), Some("NAME_INVALID_CHAR".to_json()))
  for key in ["title", "reason", "suggestion"] {
    assert_true(fields.get(key) is Some(String(_)))
  }
  assert_true(fields.get("examples") is Some(Array(_)))
  assert_eq(@moonportcheck.render_rules_json([]), "[]")
}

///|
test "rule text explains the selected rule and safely quotes control characters" {
  guard @moonportcheck.explain("NAME_INVALID_CHAR") is Some(rule) else {
    fail("Known rule is missing")
  }
  let text = @moonportcheck.render_rules_text([rule])
  assert_true(text.contains(rule.code))
  assert_true(text.contains(rule.title))
  assert_true(text.contains(rule.reason))
  assert_true(text.contains(rule.suggestion))
  assert_true(text.contains("bad\\nname"))
  assert_false(text.contains("bad\nname"))
  assert_eq(
    @moonportcheck.render_rules_text(@moonportcheck.rules()),
    @moonportcheck.render_rules_text(@moonportcheck.rules().rev()),
  )
}

///|
test "catalog arrays are independent across calls" {
  let changed = @moonportcheck.rules()
  assert_eq(changed.length(), 15)
  changed[0].examples.push("injected example")
  let fresh = @moonportcheck.rules()
  assert_false(fresh[0].examples.contains("injected example"))
  guard @moonportcheck.explain(fresh[0].code) is Some(rule) else {
    fail("Known rule is missing")
  }
  assert_false(rule.examples.contains("injected example"))
}
