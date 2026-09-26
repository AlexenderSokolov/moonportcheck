///|
test "manifest preserves dangerous path as an audit finding" {
  let text = "[{\"path\":\"../CON\",\"kind\":\"file\"},{\"path\":\"\",\"kind\":\"directory\"}]"
  guard @moonportcheck.parse_manifest(text) is Ok(entries) else {
    fail("valid entries must parse")
  }
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].path, "../CON")
  let result = @moonportcheck.audit(entries)
  assert_true(result.diagnostics.any(d => d.code == "PATH_DOT_COMPONENT"))
}

///|
test "manifest accepts empty arrays and CRLF with Unicode" {
  @test.assert_eq(@moonportcheck.parse_manifest("[]"), Ok([]))
  guard @moonportcheck.parse_manifest(
      "[\r\n{\"path\":\"研究/中文🙂\",\"kind\":\"file\"}\r\n]",
    )
    is Ok(entries) else {
    fail("unicode manifest must parse")
  }
  assert_eq(entries[0].path, "研究/中文🙂")
}

///|
test "wrong JSON shapes and kinds are schema errors" {
  for
    text in [
      "{}", "null", "1", "[1]", "[{}]", "[{\"path\":1,\"kind\":\"file\"}]", "[{\"path\":\"a\",\"kind\":\"link\"}]",
      "[{\"path\":\"a\"}]",
    ] {
    guard @moonportcheck.parse_manifest(text) is Err(error) else {
      fail("bad schema accepted")
    }
    assert_eq(error.code, "INPUT_SCHEMA")
  }
}

///|
test "invalid JSON and unpaired surrogate escape do not become filenames" {
  for
    text in [
      "[", "[{\"path\":\"a\",}]", "[{\"path\":\"\\ud800\",\"kind\":\"file\"}]",
    ] {
    guard @moonportcheck.parse_manifest(text) is Err(error) else {
      fail("invalid JSON accepted")
    }
    assert_eq(error.code, "INPUT_JSON")
  }
}
