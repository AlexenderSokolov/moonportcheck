///|
/// Fixed, hand-authored fixtures shared by the two execution backends.
fn main {
  let cases = [
    [],
    ["中文/实验 1.txt", ".hidden", "emoji/🙂.txt"],
    ["CON.txt", "prn.tar.gz", "COM¹", "lpt².txt", "LPT³", "COM9"],
    ["COM10", "LPT0", ".CON", "x.NUL"],
    ["", "/a", "C:a", "\\\\server\\share", "a/../b", "a//b", "a/"],
    ["a\\b", "a<b", "a:b", "bad\nfile", "bad\u{0000}file", "bad\u{001b}file"],
    ["Data/a", "data/b", "ROOT/c", "root/d"],
    ["x", "x", "x/y", "X/z"],
    ["é/a", "é/b", "É/c"],
    ["研究/结果", "研究/结果", "文件.", "文件 "],
    ["folder/z", "Folder/a", "aux.txt", "a", "a/child", "a"],
  ]
  for paths in cases {
    let entries : Array[@moonportcheck.PathEntry] = paths.map(p => {
      path: p,
      kind: @moonportcheck.File,
    })
    println(@moonportcheck.render_json(@moonportcheck.audit(entries)))
    println(@moonportcheck.render_json(@moonportcheck.audit(entries.rev())))
  }
  println(
    @moonportcheck.render_json(
      @moonportcheck.audit([
        { path: "目录", kind: @moonportcheck.Directory, },
        { path: "目录/a", kind: @moonportcheck.File, },
        { path: "文件", kind: @moonportcheck.File, },
        { path: "文件", kind: @moonportcheck.Directory, },
      ]),
    ),
  )
  println(@moonportcheck.render_rules_json(@moonportcheck.rules()))
  println(@moonportcheck.render_rules_json(@moonportcheck.rules().rev()))
  for paths in cases {
    let entries : Array[@moonportcheck.PathEntry] = paths.map(p => {
      path: p,
      kind: @moonportcheck.File,
    })
    println(
      @moonportcheck.render_detailed_json(
        @moonportcheck.audit_with_options(
          entries,
          @moonportcheck.default_audit_options(),
        ),
      ),
    )
    println(
      @moonportcheck.render_detailed_json(
        @moonportcheck.audit_with_options(
          entries.rev(),
          @moonportcheck.default_audit_options(),
        ),
      ),
    )
  }
  let detailed = @moonportcheck.audit_with_options(
    [
      { path: "artifact", kind: @moonportcheck.File, },
      { path: "artifact/report", kind: @moonportcheck.File, },
      { path: "artifact/report", kind: @moonportcheck.File, },
    ],
    @moonportcheck.default_audit_options(),
  )
  println(@moonportcheck.render_detailed_json(detailed))
  println(
    @moonportcheck.render_detailed_json(
      @moonportcheck.with_scan_issues(detailed, [
        {
          code: "SCAN_LINK_SKIPPED",
          path: "link",
          message: "Link was not followed.",
        },
      ]),
    ),
  )
  let glob_cases : Array[(String, String, @moonportcheck.EntryKind)] = [
    ("*.txt", "notes/a.txt", @moonportcheck.File),
    ("**/*.txt", "notes/a.txt", @moonportcheck.File),
    ("**/?.txt", "数据/🙂.txt", @moonportcheck.File),
    ("cache/", "cache", @moonportcheck.File),
    ("cache/", "cache", @moonportcheck.Directory),
    ("cache/", "cache/nested/file", @moonportcheck.File),
    ("build", "build/log", @moonportcheck.File),
    ("**", "a/../b", @moonportcheck.File),
    ("**/", "topfile", @moonportcheck.File),
    ("a/**/b", "a/b", @moonportcheck.File),
    ("a/*/b", "a/b", @moonportcheck.File),
    ("**/", "a/file", @moonportcheck.File),
  ]
  for (raw, path, kind) in glob_cases {
    let compiled = match @moonportcheck.parse_pattern(raw) {
      Ok(pattern) => pattern
      Err(_) => abort("Invalid parity pattern")
    }
    println(
      @moonportcheck.pattern_matches(compiled, { path, kind, })
      .to_json()
      .stringify(),
    )
  }
}
