///|
fn parsed_pattern(text : String) -> @moonportcheck.PathPattern raise {
  match @moonportcheck.parse_pattern(text) {
    Ok(pattern) => pattern
    Err(error) => fail("Valid pattern rejected: " + text + "; " + error.message)
  }
}

///|
fn pattern_file(pattern : @moonportcheck.PathPattern, path : String) -> Bool {
  @moonportcheck.pattern_matches(pattern, { path, kind: @moonportcheck.File, })
}

///|
test "patterns match entire case-sensitive relative paths" {
  let pattern = parsed_pattern("data/report.txt")
  assert_true(pattern_file(pattern, "data/report.txt"))
  assert_false(pattern_file(pattern, "Data/report.txt"))
  assert_false(pattern_file(pattern, "data/Report.txt"))
  assert_false(pattern_file(pattern, "other/data/report.txt"))
  assert_false(pattern_file(pattern, "report.txt"))
  let unicode = parsed_pattern("研究/结果.txt")
  assert_true(pattern_file(unicode, "研究/结果.txt"))
  assert_false(pattern_file(unicode, "研究/結果.txt"))
}

///|
test "segment star matches zero or more scalar characters without crossing slash" {
  let pattern = parsed_pattern("a*b")
  for path in ["ab", "a长🙂b", "a space b"] {
    assert_true(pattern_file(pattern, path))
  }
  for path in ["a/x/b", "a/b", "a", "b", "zaab"] {
    assert_false(pattern_file(pattern, path))
  }
  let csv = parsed_pattern("*.csv")
  assert_true(pattern_file(csv, ".csv"))
  assert_true(pattern_file(csv, "results.csv"))
  assert_false(pattern_file(csv, "nested/results.csv"))
}

///|
test "question mark consumes one Unicode scalar rather than one UTF16 code unit" {
  let single = parsed_pattern("?")
  for path in ["a", "中", "🙂", "é"] {
    assert_true(pattern_file(single, path))
  }
  assert_false(pattern_file(single, "é"))
  assert_false(pattern_file(single, "ab"))
  let two = parsed_pattern("??")
  assert_true(pattern_file(two, "é"))
  assert_true(pattern_file(two, "🙂中"))
  assert_false(pattern_file(two, "🙂"))
  assert_false(pattern_file(parsed_pattern("a?b"), "a/x/b"))
}

///|
test "whole recursive segment matches zero one or many path segments" {
  let pattern = parsed_pattern("a/**/b")
  for path in ["a/b", "a/x/b", "a/x/y/b"] {
    assert_true(pattern_file(pattern, path))
  }
  for path in ["b", "xa/b", "a/x/c"] {
    assert_false(pattern_file(pattern, path))
  }
  let suffix = parsed_pattern("**/*.tmp")
  for path in ["result.tmp", "data/result.tmp", "a/b/result.tmp"] {
    assert_true(pattern_file(suffix, path))
  }
  let repeated = parsed_pattern("**/**/b")
  for path in ["b", "a/b", "a/x/b"] {
    assert_true(pattern_file(repeated, path))
  }
  assert_true(pattern_file(parsed_pattern("cache/**"), "cache"))
}

///|
test "matching an implicit directory excludes its descendants" {
  let exact = parsed_pattern("cache")
  assert_true(pattern_file(exact, "cache/data/report.txt"))
  assert_false(pattern_file(exact, "other/cache/report.txt"))
  let glob = parsed_pattern("build-*")
  assert_true(pattern_file(glob, "build-debug/nested/output.bin"))
  assert_false(pattern_file(glob, "src/build-debug/output.bin"))
  let nested = parsed_pattern("**/cache")
  assert_true(pattern_file(nested, "src/cache/deep/file"))
}

///|
test "trailing slash requires a real or implicit directory prefix" {
  let pattern = parsed_pattern("cache/")
  assert_false(pattern_file(pattern, "cache"))
  assert_true(
    @moonportcheck.pattern_matches(pattern, {
      path: "cache",
      kind: @moonportcheck.Directory,
    }),
  )
  assert_true(pattern_file(pattern, "cache/entry"))
  assert_false(pattern_file(pattern, "cache2/entry"))
  let recursive = parsed_pattern("**/")
  assert_false(pattern_file(recursive, "root-file.txt"))
  assert_true(
    @moonportcheck.pattern_matches(recursive, {
      path: "empty",
      kind: @moonportcheck.Directory,
    }),
  )
  assert_true(pattern_file(recursive, "directory/file.txt"))
  let tail = parsed_pattern("cache/**/")
  assert_false(pattern_file(tail, "cache"))
  assert_true(pattern_file(tail, "cache/entry"))
}

///|
test "structurally invalid paths cannot be hidden by any pattern" {
  for text in ["**", "*", "**/", "a/**"] {
    let pattern = parsed_pattern(text)
    for
      path in [
        "", "/root/file", "\\root", "\\\\server\\share", "C:file", "D:/file", "a//b",
        "a/", "./a", "a/../b",
      ] {
      assert_false(pattern_file(pattern, path))
      assert_false(
        @moonportcheck.pattern_matches(pattern, {
          path,
          kind: @moonportcheck.Directory,
        }),
      )
    }
  }
}

///|
test "explicit scope can match nonstructural name problems without normalizing names" {
  let all = parsed_pattern("**")
  for path in ["CON.txt", "report.", "a ", "bad\\name", "bad\nname", "dir/a:b"] {
    assert_true(pattern_file(all, path))
  }
  let direct = parsed_pattern("CON.txt")
  assert_true(pattern_file(direct, "CON.txt"))
  assert_false(pattern_file(parsed_pattern("bad/name"), "bad\\name"))
}

///|
test "invalid pattern grammar returns PATTERN_INVALID" {
  for
    text in [
      "", "/", "/a", "C:a", "D:/a", "a\\b", "a//b", "a//", "./a", "a/../b", ".",
      "..", "!a", "a[b]", "a]b", "a{b}", "a}b", "a**b", "***", "**x", "x**", "a/***/b",
      "a\n", "a\u{0000}", "a\u{001f}", "a\u{007f}", "a\u{0085}", "a\u{009f}",
    ] {
    guard @moonportcheck.parse_pattern(text) is Err(error) else {
      fail("Invalid pattern accepted: " + text)
    }
    assert_eq(error.code, "PATTERN_INVALID")
    assert_true(error.message.length() > 0)
  }
}

///|
test "literal punctuation and internal exclamation marks remain valid" {
  for text in [".git", "a!b", "a/!b", "a b", "a.b", "中文", "a/b:c", "a..b"] {
    let pattern = parsed_pattern(text)
    assert_true(pattern_file(pattern, text))
  }
}

///|
test "deep relative paths use iterative matching" {
  let parts = Array::make(5000, "branch")
  parts.push("leaf.txt")
  let path = parts.join("/")
  assert_true(pattern_file(parsed_pattern("**/leaf.txt"), path))
  assert_false(pattern_file(parsed_pattern("**/missing.txt"), path))
}

///|
test "long common prefixes and repeated stars do not require recursive backtracking" {
  let common = Array::make(512, "a").join("")
  assert_true(pattern_file(parsed_pattern(common + "*z"), common + "🙂z"))
  assert_false(pattern_file(parsed_pattern(common + "*z"), common + "🙂y"))
  let stars = Array::make(128, "*a").join("") + "*z"
  assert_false(
    pattern_file(parsed_pattern(stars), Array::make(256, "a").join("") + "y"),
  )
  assert_true(
    pattern_file(parsed_pattern(stars), Array::make(256, "a").join("") + "z"),
  )
}
