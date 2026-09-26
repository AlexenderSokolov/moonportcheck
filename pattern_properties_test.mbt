///|
// A small recursive specification is independent of the production iterative matcher.
fn reference_segment(
  pattern : Array[Char],
  text : Array[Char],
  p : Int,
  t : Int,
) -> Bool {
  if p == pattern.length() {
    return t == text.length()
  }
  if pattern[p] == '*' {
    return reference_segment(pattern, text, p + 1, t) ||
      (t < text.length() && reference_segment(pattern, text, p, t + 1))
  }
  t < text.length() &&
  (pattern[p] == '?' || pattern[p] == text[t]) &&
  reference_segment(pattern, text, p + 1, t + 1)
}

///|
fn reference_path(
  pattern : Array[String],
  text : Array[String],
  p : Int,
  t : Int,
) -> Bool {
  if p == pattern.length() {
    return t == text.length()
  }
  if pattern[p] == "**" {
    return reference_path(pattern, text, p + 1, t) ||
      (t < text.length() && reference_path(pattern, text, p, t + 1))
  }
  t < text.length() &&
  reference_segment(pattern[p].iter().collect(), text[t].iter().collect(), 0, 0) &&
  reference_path(pattern, text, p + 1, t + 1)
}

///|
test "glob matcher agrees with a bounded recursive specification across path prefixes" {
  let atoms = ["a", "b", "aa", "ab"]
  let paths = atoms.copy()
  for a in atoms {
    for b in atoms {
      paths.push(a + "/" + b)
      for c in atoms {
        paths.push(a + "/" + b + "/" + c)
      }
    }
  }
  let patterns = [
    "*", "?", "a*", "*b", "a?", "*a*b", "a/*", "*/b", "**", "**/a", "a/**", "a/**/b",
    "**/?/**", "a/*/b", "**/**/b",
  ]
  for raw in patterns {
    let compiled = match @moonportcheck.parse_pattern(raw) {
      Ok(pattern) => pattern
      Err(_) => fail("Valid pattern rejected: " + raw)
    }
    let pattern = raw.split("/").map(s => s.to_owned()).collect()
    for path in paths {
      let parts = path.split("/").map(s => s.to_owned()).collect()
      let mut expected = false
      for length in 1..<=parts.length() {
        if reference_path(pattern, Array::makei(length, i => parts[i]), 0, 0) {
          expected = true
          break
        }
      }
      let actual = @moonportcheck.pattern_matches(compiled, {
        path,
        kind: @moonportcheck.File,
      })
      if actual != expected {
        fail("Matcher differs from specification: " + raw + " -> " + path)
      }
    }
  }
}
