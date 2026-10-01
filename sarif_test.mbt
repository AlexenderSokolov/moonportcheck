///| Test SARIF 2.1.0 reporting: URI escaping, locations without fabricated

///| source lines, rule metadata and completeness expression.

///|
fn sarif_of(entries : Array[@moonportcheck.PathEntry]) -> String {
  @moonportcheck.render_check_sarif(detailed(entries))
}

///|
test "uri_escape_path percent encodes non-ASCII and spaces but keeps separators" {
  assert_eq(@moonportcheck.uri_escape_path("CON.txt"), "CON.txt")
  assert_eq(
    @moonportcheck.uri_escape_path("研究/结果.txt"),
    "%E7%A0%94%E7%A9%B6/%E7%BB%93%E6%9E%9C.txt",
  )
  assert_eq(@moonportcheck.uri_escape_path("a#b?c d"), "a%23b%3Fc%20d")
  assert_eq(@moonportcheck.uri_escape_path("plain-ish_2.0~"), "plain-ish_2.0~")
}

///|
test "sarif_report_is_two_point_one_with_uri_locations_and_no_region" {
  let sarif = sarif_of(files(["CON.txt", "研究/结果.txt ", "../bad"]))
  assert_true(sarif.has_prefix("{\"version\":\"2.1.0\""))
  assert_true(
    sarif.contains(
      "\"$schema\":\"https://json.schemastore.org/sarif-2.1.0.json\"",
    ),
  )
  assert_true(sarif.contains("\"ruleId\":\"NAME_RESERVED\""))
  assert_true(sarif.contains("\"ruleId\":\"PATH_DOT_COMPONENT\""))
  assert_true(sarif.contains("\"ruleId\":\"NAME_TRAILING_DOT_SPACE\""))
  assert_true(sarif.contains("\"level\":\"error\""))
  assert_true(
    sarif.contains("\"uri\":\"%E7%A0%94%E7%A9%B6/%E7%BB%93%E6%9E%9C.txt%20\""),
  )
  assert_true(sarif.contains("\"uri\":\"CON.txt\""))
  assert_true(sarif.contains("\"uri\":\"../bad\""))
  assert_true(sarif.contains("\"executionSuccessful\":true"))
  // The model has no source line numbers; a location must never fabricate one.
  assert_true(sarif.contains("startLine") == false)
  assert_true(sarif.contains("startColumn") == false)
  // Every emitted rule appears in the driver rule catalog.
  assert_true(sarif.contains("\"id\":\"NAME_RESERVED\""))
  assert_true(sarif.contains("\"defaultConfiguration\":{\"level\":\"error\"}"))
}

///|
test "sarif_report_expresses_scan_issues_and_incomplete_runs" {
  let report = @moonportcheck.with_scan_issues(detailed(files(["CON.txt"])), [
    issue("SCAN_IO_ERROR", "logs/x", "Cannot read entry metadata."),
  ])
  let sarif = @moonportcheck.render_check_sarif(report)
  assert_true(sarif.contains("\"executionSuccessful\":false"))
  assert_true(sarif.contains("\"ruleId\":\"SCAN_IO_ERROR\""))
  assert_true(sarif.contains("\"level\":\"note\""))
  assert_true(sarif.contains("\"uri\":\"logs/x\""))
  assert_true(
    sarif.contains("\"message\":{\"text\":\"Cannot read entry metadata.\"}"),
  )
}
