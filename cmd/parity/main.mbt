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
  let scope_fixtures : Array[(Array[String], Array[@moonportcheck.PathEntry])] = [
    (
      ["*.tmp", "cache/"],
      [
        { path: "results.tmp", kind: @moonportcheck.File, },
        { path: "notes/a.txt", kind: @moonportcheck.File, },
        { path: "cache", kind: @moonportcheck.Directory, },
        { path: "cache/x.tmp", kind: @moonportcheck.File, },
        { path: "nested/c.tmp", kind: @moonportcheck.File, },
      ],
    ),
    (
      ["**"],
      [
        { path: "/abs", kind: @moonportcheck.File, },
        { path: "CON.txt", kind: @moonportcheck.File, },
        { path: "ok/a.txt", kind: @moonportcheck.File, },
      ],
    ),
  ]
  for (patterns, entries) in scope_fixtures {
    let scope = match @moonportcheck.parse_scope(patterns) {
      Ok(scope) => scope
      Err(_) => abort("Invalid parity scope")
    }
    println(
      @moonportcheck.render_detailed_json(
        @moonportcheck.audit_with_exclusions(
          entries,
          @moonportcheck.default_audit_options(),
          scope,
        ),
      ),
    )
    println(
      @moonportcheck.render_detailed_json(
        @moonportcheck.audit_with_exclusions(
          entries.rev(),
          @moonportcheck.default_audit_options(),
          scope,
        ),
      ),
    )
  }
  let snapshot = match
    @moonportcheck.build_snapshot(
      [
        { path: "目录/a.txt", kind: @moonportcheck.File, },
        { path: "数据", kind: @moonportcheck.Directory, },
        { path: "results.tmp", kind: @moonportcheck.File, },
      ],
      [
        {
          code: "SCAN_LINK_SKIPPED",
          path: "link",
          message: "Link was not followed.",
        },
      ],
      ["cache/", "*.tmp"],
    ) {
    Ok(snapshot) => snapshot
    Err(_) => abort("Invalid parity snapshot")
  }
  println(@moonportcheck.render_snapshot_json(snapshot))
  println(
    @moonportcheck.render_snapshot_json(
      match
        @moonportcheck.parse_snapshot(
          @moonportcheck.render_snapshot_json(snapshot),
        ) {
        Ok(parsed) => parsed
        Err(_) => abort("Snapshot round trip failed")
      },
    ),
  )
  let audit_target = match
    @moonportcheck.build_snapshot(
      [
        { path: "CON.txt", kind: @moonportcheck.File, },
        { path: "cache", kind: @moonportcheck.Directory, },
        { path: "cache/x.bin", kind: @moonportcheck.File, },
        { path: "results.tmp", kind: @moonportcheck.File, },
      ],
      [],
      ["*.tmp", "cache/"],
    ) {
    Ok(snapshot) => snapshot
    Err(_) => abort("Invalid parity snapshot")
  }
  println(
    @moonportcheck.render_detailed_json(
      match @moonportcheck.audit_snapshot(audit_target, ["results.tmp"]) {
        Ok(report) => report
        Err(_) => abort("Snapshot audit failed")
      },
    ),
  )
  let diff_before = match
    @moonportcheck.build_snapshot(
      [
        { path: "a.txt", kind: @moonportcheck.File, },
        { path: "C.txt", kind: @moonportcheck.File, },
        { path: "dir", kind: @moonportcheck.Directory, },
      ],
      [],
      [],
    ) {
    Ok(snapshot) => snapshot
    Err(_) => abort("Invalid parity snapshot")
  }
  let diff_after = match
    @moonportcheck.build_snapshot(
      [
        { path: "A.txt", kind: @moonportcheck.File, },
        { path: "C.txt", kind: @moonportcheck.Directory, },
        { path: "dir", kind: @moonportcheck.Directory, },
        { path: "new.tmp", kind: @moonportcheck.File, },
      ],
      [],
      [],
    ) {
    Ok(snapshot) => snapshot
    Err(_) => abort("Invalid parity snapshot")
  }
  println(
    @moonportcheck.render_snapshot_diff_json(
      match @moonportcheck.diff_snapshots(diff_before, diff_after) {
        Ok(diff) => diff
        Err(_) => abort("Parity snapshot diff failed")
      },
    ),
  )
  let baseline_report = match
    @moonportcheck.audit_snapshot(audit_target, ["results.tmp"]) {
    Ok(report) => report
    Err(_) => abort("Snapshot audit failed")
  }
  let baseline = match @moonportcheck.build_baseline(baseline_report) {
    Ok(baseline) => baseline
    Err(_) => abort("Baseline build failed")
  }
  println(@moonportcheck.render_baseline_json(baseline))
  println(
    @moonportcheck.render_baseline_diff_json(
      @moonportcheck.diff_with_baseline(
        baseline,
        match
          @moonportcheck.audit_snapshot(audit_target, ["CON.txt", "results.tmp"]) {
          Ok(report) => report
          Err(_) => abort("Snapshot audit failed")
        },
      ),
    ),
  )
  // M12: baseline create is a parse-rebuild round trip. Feed the rendered
  // report document back through parse_detailed_report and build_baseline and
  // the resulting document must be byte-identical to the source baseline.
  println(
    @moonportcheck.render_baseline_json(
      match
        @moonportcheck.build_baseline(
          match
            @moonportcheck.parse_detailed_report(
              @moonportcheck.render_detailed_json(baseline_report),
            ) {
            Ok(report) => report
            Err(_) => abort("Detailed report parse failed")
          },
        ) {
        Ok(baseline) => baseline
        Err(_) => abort("Baseline rebuild failed")
      },
    ),
  )
}
