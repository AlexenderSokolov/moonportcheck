///|
test "JSON report includes usable counts rules and scope" {
  let report = @moonportcheck.audit(files(["CON.txt", "中文/正常文件"]))
  let text = @moonportcheck.render_json(report)
  assert_true(text.contains("\"schema_version\":1"))
  assert_true(text.contains("\"profile\":\"portable-windows-v1\""))
  assert_true(text.contains("\"files\":2"))
  assert_true(text.contains("\"code\":\"NAME_RESERVED\""))
  assert_true(text.contains("\"source\":\"manifest\""))
}

///|
test "text output escapes terminal control characters" {
  let report = @moonportcheck.audit(files(["bad\nname\u{001b}[31m"]))
  let text = @moonportcheck.render_text(report)
  assert_true(text.contains("NAME_INVALID_CHAR"))
  assert_true(text.contains("bad\\nname\\u001b[31m"))
  assert_false(text.contains("\u{001b}"))
}

///|
test "both report formats stay stable under input permutations" {
  let input = files(["Z/a", "z/b", "a", "a", "a/b", "AUX.txt"])
  let before = @moonportcheck.audit(input)
  let after = @moonportcheck.audit(input.rev())
  assert_eq(
    @moonportcheck.render_json(before),
    @moonportcheck.render_json(after),
  )
  assert_eq(
    @moonportcheck.render_text(before),
    @moonportcheck.render_text(after),
  )
}
