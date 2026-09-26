///|
priv struct PathCounts {
  mut files : Int
  mut directories : Int
}

///|
/// One canonical prefix stores distinct spellings, not pairs of entries.
priv struct Prefix {
  spellings : Map[String, Bool]
  mut file : Bool
  mut directory : Bool
}

///|
fn[V] sorted_keys(map : Map[String, V]) -> Array[String] {
  let keys = map.keys().collect()
  keys.sort_by(ordinal_compare)
  keys
}

///|
/// MoonBit String.Compare is length-first. Reports use UTF-16 ordinal order.
fn ordinal_compare(a : String, b : String) -> Int {
  for i in 0..<a.length().min(b.length()) {
    let order = a[i].compare(b[i])
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
fn ascii_lower(text : String) -> String {
  String::from_iter(
    text
    .iter()
    .map(c => {
      if c >= 'A' && c <= 'Z' {
        (c.to_int() + 32).unsafe_to_char()
      } else {
        c
      }
    }),
  )
}

///|
fn diagnostic(
  code : String,
  paths : Array[String],
  occurrences : Int,
) -> Diagnostic {
  let message = match code {
    "PATH_EMPTY" => "A relative path cannot be empty."
    "PATH_ABSOLUTE" => "Use a root-relative path, not an absolute or UNC path."
    "PATH_DRIVE" => "Drive-qualified paths are not root-relative."
    "PATH_EMPTY_COMPONENT" =>
      "Path components cannot be empty; omit trailing slashes."
    "PATH_DOT_COMPONENT" =>
      "Dot and parent components are not normalized or accepted."
    "NAME_INVALID_CHAR" =>
      "A component contains a Windows-reserved character or U+0000..U+001F."
    "NAME_RESERVED" =>
      "A component uses a Windows device name, including its extension form."
    "NAME_TRAILING_DOT_SPACE" =>
      "A component ends in an ASCII space or a period."
    "PATH_DUPLICATE" =>
      "The same exact path occurs more than once in the input."
    "PATH_CASE_COLLISION" =>
      "Distinct prefix spellings collide under ASCII case folding."
    "PATH_KIND_CONFLICT" => "A folded path denotes both a file and a directory."
    _ => "Path portability issue."
  }
  { code, severity: "error", paths, occurrences, message, }
}

///|
fn sort_diagnostics(items : Array[Diagnostic]) -> Unit {
  items.sort_by((a, b) => {
    let code_order = ordinal_compare(a.code, b.code)
    if code_order != 0 {
      return code_order
    }
    let n = a.paths.length().min(b.paths.length())
    for i in 0..<n {
      let order = ordinal_compare(a.paths[i], b.paths[i])
      if order != 0 {
        return order
      }
    }
    a.paths.length().compare(b.paths.length())
  })
}

///|
fn reserved(component : String) -> Bool {
  let folded = ascii_lower(component)
  let stem = match folded.split_once(".") {
    Some((head, _)) => head.to_owned()
    None => folded
  }
  match stem {
    "con" | "prn" | "aux" | "nul" => true
    _ => {
      let chars = stem.iter().collect()
      chars.length() == 4 &&
      (stem.has_prefix("com") || stem.has_prefix("lpt")) &&
      (
        (chars[3] >= '1' && chars[3] <= '9') ||
        chars[3] == '¹' ||
        chars[3] == '²' ||
        chars[3] == '³'
      )
    }
  }
}

///|
/// Validate spelling separately from hierarchy construction.
fn check_path(
  path : String,
  count : Int,
  out : Array[Diagnostic],
) -> Array[String]? {
  let found : Map[String, Bool] = Map([])
  let parts = path.split("/").map(p => p.to_owned()).collect()
  let mut structural = false
  if path == "" {
    found["PATH_EMPTY"] = true
    structural = true
  }
  if path.has_prefix("/") || path.has_prefix("\\") {
    found["PATH_ABSOLUTE"] = true
    structural = true
  }
  let leading = path.iter().take(2).collect()
  if leading.length() == 2 &&
    leading[1] == ':' &&
    (
      (leading[0] >= 'a' && leading[0] <= 'z') ||
      (leading[0] >= 'A' && leading[0] <= 'Z')
    ) {
    found["PATH_DRIVE"] = true
    structural = true
  }
  for part in parts {
    if part == "" && path != "" {
      found["PATH_EMPTY_COMPONENT"] = true
      structural = true
    }
    if part == "." || part == ".." {
      found["PATH_DOT_COMPONENT"] = true
      structural = true
    } else if part.has_suffix(".") || part.has_suffix(" ") {
      found["NAME_TRAILING_DOT_SPACE"] = true
    }
    for c in part.iter() {
      if c.to_int() < 32 ||
        (match c {
          '<' | '>' | ':' | '"' | '\\' | '|' | '?' | '*' => true
          _ => false
        }) {
        found["NAME_INVALID_CHAR"] = true
      }
    }
    if reserved(part) {
      found["NAME_RESERVED"] = true
    }
  }
  for code in sorted_keys(found) {
    out.push(diagnostic(code, [path], count))
  }
  if structural {
    None
  } else {
    Some(parts)
  }
}

///| Audit supplied entries. Completeness means the supplied list was checked,

///|
/// not that it describes every file in a directory or every filesystem rule.
pub fn audit(entries : Array[PathEntry]) -> Report {
  let counts : Map[String, PathCounts] = Map([])
  let prefixes : Map[String, Prefix] = Map([])
  let diagnostics : Array[Diagnostic] = []
  let mut files = 0
  let mut directories = 0
  for entry in entries {
    let count = match counts.get(entry.path) {
      Some(c) => c
      None => {
        let c = { files: 0, directories: 0, }
        counts[entry.path] = c
        c
      }
    }
    match entry.kind {
      File => {
        files += 1
        count.files += 1
      }
      Directory => {
        directories += 1
        count.directories += 1
      }
    }
  }
  for path in sorted_keys(counts) {
    let count = counts[path]
    let total = count.files + count.directories
    if total > 1 {
      diagnostics.push(diagnostic("PATH_DUPLICATE", [path], total))
    }
    guard check_path(path, total, diagnostics) is Some(parts) else { continue }
    let mut prefix = ""
    for i, part in parts {
      prefix = if i == 0 { part } else { prefix + "/" + part }
      let folded = ascii_lower(prefix)
      let node = match prefixes.get(folded) {
        Some(p) => p
        None => {
          let p = { spellings: Map([]), file: false, directory: false, }
          prefixes[folded] = p
          p
        }
      }
      node.spellings[prefix] = true
      if i < parts.length() - 1 || count.directories > 0 {
        node.directory = true
      }
      if i == parts.length() - 1 && count.files > 0 {
        node.file = true
      }
    }
  }
  for node in prefixes.values() {
    let paths = sorted_keys(node.spellings)
    if paths.length() > 1 {
      diagnostics.push(diagnostic("PATH_CASE_COLLISION", paths, paths.length()))
    }
    if node.file && node.directory {
      diagnostics.push(diagnostic("PATH_KIND_CONFLICT", paths, paths.length()))
    }
  }
  sort_diagnostics(diagnostics)
  {
    schema_version: 1,
    profile: "portable-windows-v1",
    source: "manifest",
    complete: true,
    summary: {
      entries: entries.length(),
      files,
      directories,
      diagnostic_groups: diagnostics.length(),
      scan_issues: 0,
    },
    diagnostics,
    limitations: [
      "Only ASCII case folding is checked; Unicode case equivalence and normalization are not checked.",
      "Path length limits, filesystem-specific rules, permissions and destination state are not checked.",
      "A manifest report covers only supplied entries; a directory scan is not an atomic snapshot.",
    ],
  }
}
