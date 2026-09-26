///|
fn files(paths : Array[String]) -> Array[@moonportcheck.PathEntry] {
  paths.map(p => { path: p, kind: @moonportcheck.File, })
}

///|
fn codes(report : @moonportcheck.Report) -> Array[String] {
  report.diagnostics.map(d => d.code)
}

///|
test "reserved name and trailing dot must be diagnosed" {
  let report = @moonportcheck.audit(
    files(["assets/CON.txt", "notes/report.md."]),
  )
  @test.assert_eq(codes(report), ["NAME_RESERVED", "NAME_TRAILING_DOT_SPACE"])
  assert_eq(report.summary.files, 2)
}

///|
test "ordinary Unicode dotfiles and spaces pass without changing names" {
  let report = @moonportcheck.audit(
    files(["研究/实验 1.csv", ".gitignore", "空格 名/结果.txt"]),
  )
  assert_eq(report.diagnostics.length(), 0)
  assert_eq(report.summary.files, 3)
  assert_true(report.complete)
  assert_true(report.limitations.length() > 0)
}

///|
test "implicit intermediate directory casing is visible" {
  let report = @moonportcheck.audit(files(["Data/a.csv", "data/b.csv"]))
  assert_eq(codes(report), ["PATH_CASE_COLLISION"])
  @test.assert_eq(report.diagnostics[0].paths, ["Data", "data"])
}

///|
test "duplicate entries are grouped and counted" {
  let report = @moonportcheck.audit(files(["a.txt", "a.txt", "a.txt"]))
  assert_eq(codes(report), ["PATH_DUPLICATE"])
  @test.assert_eq(report.diagnostics[0].paths, ["a.txt"])
  assert_eq(report.diagnostics[0].occurrences, 3)
}

///|
test "file cannot also be an implicit directory" {
  let report = @moonportcheck.audit(files(["data", "data/a.csv"]))
  assert_eq(codes(report), ["PATH_KIND_CONFLICT"])
  @test.assert_eq(report.diagnostics[0].paths, ["data"])
}

///|
test "all device names including extensions and superscripts are reserved" {
  for
    name in [
      "CON", "con.txt", "PrN.tar.gz", "AUX", "nul", "COM1", "COM9.txt", "LPT1", "LPT9",
      "COM¹", "com².txt", "COM³", "LPT¹", "LPT²", "lpt³.log",
    ] {
    assert_true(
      codes(@moonportcheck.audit(files([name]))).contains("NAME_RESERVED"),
    )
  }
  for
    name in [
      "COM0", "COM10", "LPT0", "LPT10", "console", "AUXiliary", ".CON", "COM⁴",
      "x.NUL",
    ] {
    assert_false(
      codes(@moonportcheck.audit(files([name]))).contains("NAME_RESERVED"),
    )
  }
}

///|
test "structural paths are rejected without normalization" {
  for
    pair in [
      ("", "PATH_EMPTY"),
      ("/a", "PATH_ABSOLUTE"),
      ("\\\\host\\share", "PATH_ABSOLUTE"),
      ("C:a", "PATH_DRIVE"),
      ("a//b", "PATH_EMPTY_COMPONENT"),
      ("a/", "PATH_EMPTY_COMPONENT"),
      ("a/../b", "PATH_DOT_COMPONENT"),
      ("./a", "PATH_DOT_COMPONENT"),
    ] {
    assert_true(codes(@moonportcheck.audit(files([pair.0]))).contains(pair.1))
  }
  let report = @moonportcheck.audit(files(["a/../b", "b"]))
  assert_false(codes(report).contains("PATH_DUPLICATE"))
}

///|
test "invalid characters and tail whitespace are detected at every depth" {
  for
    name in [
      "a<b", "a>b", "a:b", "a\"b", "a\\b", "a|b", "a?b", "a*b", "a\nfile", "a\u{0000}b",
      "a\u{001f}b",
    ] {
    assert_true(
      codes(@moonportcheck.audit(files(["dir/" + name]))).contains(
        "NAME_INVALID_CHAR",
      ),
    )
  }
  for name in ["a.", "a ", "a /b", "a./b"] {
    assert_true(
      codes(@moonportcheck.audit(files([name]))).contains(
        "NAME_TRAILING_DOT_SPACE",
      ),
    )
  }
}

///|
test "explicit directory coexists with implicit directory" {
  let report = @moonportcheck.audit([
    { path: "dir", kind: @moonportcheck.Directory, },
    { path: "dir/file", kind: @moonportcheck.File, },
  ])
  assert_eq(report.diagnostics.length(), 0)
  assert_eq(report.summary.files, 1)
  assert_eq(report.summary.directories, 1)
}

///|
test "file directory conflict is checked after ASCII folding" {
  let report = @moonportcheck.audit(files(["Data", "data/a.csv"]))
  @test.assert_eq(codes(report), ["PATH_CASE_COLLISION", "PATH_KIND_CONFLICT"])
}

///|
test "explicit kinds at same path report duplicate and kind conflict" {
  let report = @moonportcheck.audit([
    { path: "same", kind: @moonportcheck.Directory, },
    { path: "same", kind: @moonportcheck.File, },
  ])
  @test.assert_eq(codes(report), ["PATH_DUPLICATE", "PATH_KIND_CONFLICT"])
}

///|
test "ASCII folding leaves non ASCII letters distinct" {
  let report = @moonportcheck.audit(
    files(["É.txt", "é.txt", "é/中文", "é/中文"]),
  )
  assert_eq(report.diagnostics.length(), 0)
}

///|
test "input permutation does not change report and input stays intact" {
  let input = files([
    "Data/a", "data/b", "CON.txt", "data/b", "root", "root/child",
  ])
  let saved = input.copy()
  let reversed = input.rev()
  @test.assert_eq(@moonportcheck.audit(input), @moonportcheck.audit(reversed))
  @test.assert_eq(input, saved)
}

///|
test "empty manifest is complete but makes no claim about a directory" {
  let report = @moonportcheck.audit([])
  assert_eq(report.summary.entries, 0)
  assert_eq(report.source, "manifest")
  assert_true(report.complete)
}
