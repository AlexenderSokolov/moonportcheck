///|
/// A validated exclusion glob. Construct patterns with parse_pattern.
pub struct PathPattern {
  priv segments : Array[PatternSegment]
  priv directory_only : Bool
}

///|
priv enum PatternSegment {
  Recursive
  Glob(Array[Char])
}

///|
fn invalid_pattern(message : String) -> InputError {
  { code: "PATTERN_INVALID", message, }
}

///|
/// Parse a case-sensitive exclusion glob. No normalization or extension syntax is inferred.
pub fn parse_pattern(text : String) -> Result[PathPattern, InputError] {
  if text == "" {
    return Err(invalid_pattern("An exclusion pattern cannot be empty."))
  }
  if text.has_prefix("/") || text.has_prefix("\\") {
    return Err(
      invalid_pattern(
        "Exclusion patterns must be relative to the delivery root.",
      ),
    )
  }
  if text.has_prefix("!") {
    return Err(invalid_pattern("Negated exclusion patterns are not supported."))
  }
  let leading = text.iter().take(2).collect()
  if leading.length() == 2 &&
    leading[1] == ':' &&
    (
      (leading[0] >= 'a' && leading[0] <= 'z') ||
      (leading[0] >= 'A' && leading[0] <= 'Z')
    ) {
    return Err(
      invalid_pattern(
        "Drive-qualified exclusion patterns are not relative paths.",
      ),
    )
  }
  for character in text.iter() {
    let scalar = character.to_int()
    if scalar < 32 || (scalar >= 127 && scalar <= 159) {
      return Err(
        invalid_pattern(
          "Exclusion patterns cannot contain C0, DEL, or C1 control characters.",
        ),
      )
    }
    match character {
      '\\' =>
        return Err(
          invalid_pattern(
            "Use / as the pattern separator; backslashes are not supported.",
          ),
        )
      '[' | ']' | '{' | '}' =>
        return Err(
          invalid_pattern(
            "Character classes and brace extensions are not supported.",
          ),
        )
      _ => ()
    }
  }
  let directory_only = text.has_suffix("/")
  let parts = text.split("/").map(part => part.to_owned()).collect()
  let length = if directory_only { parts.length() - 1 } else { parts.length() }
  let segments : Array[PatternSegment] = []
  for i in 0..<length {
    let part = parts[i]
    if part == "" {
      return Err(
        invalid_pattern(
          "Pattern components cannot be empty; only one trailing / is allowed.",
        ),
      )
    }
    if part == "." || part == ".." {
      return Err(
        invalid_pattern(
          "Dot and parent components are not accepted in exclusion patterns.",
        ),
      )
    }
    if part == "**" {
      segments.push(Recursive)
    } else {
      if part.contains("**") {
        return Err(
          invalid_pattern("Recursive ** must occupy a whole path component."),
        )
      }
      segments.push(Glob(part.iter().collect()))
    }
  }
  Ok({ segments, directory_only, })
}

///|
/// Segment-local dynamic programming over Unicode scalar values.
fn glob_segment_matches(tokens : Array[Char], characters : Array[Char]) -> Bool {
  let mut previous = Array::make(characters.length() + 1, false)
  previous[0] = true
  for token in tokens {
    let next = Array::make(characters.length() + 1, false)
    if token == '*' {
      next[0] = previous[0]
      for i in 1..<=characters.length() {
        next[i] = previous[i] || next[i - 1]
      }
    } else {
      for i in 1..<=characters.length() {
        next[i] = previous[i - 1] &&
          (token == '?' || token == characters[i - 1])
      }
    }
    previous = next
  }
  previous[characters.length()]
}

///|
/// Recursive components may advance without consuming a path segment.
fn close_recursive_states(
  segments : Array[PatternSegment],
  states : Array[Bool],
) -> Unit {
  for i, segment in segments {
    if states[i] && segment is Recursive {
      states[i + 1] = true
    }
  }
}

///|
/// Match an entry or any implicit directory prefix. Invalid path structure never matches.
pub fn pattern_matches(pattern : PathPattern, entry : PathEntry) -> Bool {
  guard check_path(entry.path, 1, []) is Some(parts) else { return false }
  let segments = pattern.segments
  let mut states = Array::make(segments.length() + 1, false)
  states[0] = true
  close_recursive_states(segments, states)
  for index, part in parts {
    let characters = part.iter().collect()
    let next = Array::make(segments.length() + 1, false)
    for i, segment in segments {
      if !states[i] {
        continue
      }
      match segment {
        Recursive => next[i] = true
        Glob(tokens) =>
          if glob_segment_matches(tokens, characters) {
            next[i + 1] = true
          }
      }
    }
    close_recursive_states(segments, next)
    let directory = index < parts.length() - 1 || entry.kind == Directory
    if next[segments.length()] && (!pattern.directory_only || directory) {
      return true
    }
    states = next
  }
  false
}
