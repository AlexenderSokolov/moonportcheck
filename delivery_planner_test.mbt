///|
fn dp_test_mapping(
  mode : String,
  source : String,
  from : String,
  to : String,
) -> @moonportcheck.DeliveryMapping {
  { mode, source, from, to, }
}

///|
fn dp_test_spec(
  target : Array[@moonportcheck.PathEntry],
  mappings : Array[@moonportcheck.DeliveryMapping],
) -> @moonportcheck.DeliverySpec raise {
  {
    sources: [],
    target: { id: "target", snapshot: snapshot_of(target, [], []), },
    mappings,
  }
}

///|
fn dp_test_plan(
  spec : @moonportcheck.DeliverySpec,
) -> @moonportcheck.DeliveryPlan raise {
  match @moonportcheck.plan_delivery(spec) {
    Ok(plan) => plan
    Err(error) => fail(error.message)
  }
}

///|
test "delivery planner swaps files using a collision-free temporary path" {
  let plan = dp_test_plan(
    dp_test_spec(files(["a", "b", ".moonportcheck-stage-0"]), [
      dp_test_mapping("move", "target", "a", "b"),
      dp_test_mapping("move", "target", "b", "a"),
    ]),
  )
  assert_eq(plan.status, "ready")
  assert_eq(plan.operations.length(), 3)
  assert_eq(plan.temporary_paths.length(), 1)
  assert_false(plan.temporary_paths.contains(".moonportcheck-stage-0"))
}

///|
test "delivery planner copy reads initial b even after b moves" {
  let plan = dp_test_plan(
    dp_test_spec(files(["a", "b"]), [
      dp_test_mapping("move", "target", "b", "c"),
      dp_test_mapping("move", "target", "a", "b"),
      dp_test_mapping("copy", "target", "b", "d"),
    ]),
  )
  assert_eq(plan.status, "ready")
  let copies = plan.operations.filter(op => op.kind == "copy")
  assert_eq(copies.length(), 1)
  assert_eq(copies[0].origin.path, "b")
  assert_eq(copies[0].from, "c")
}

///|
test "delivery planner vacates a file before creating its directory" {
  let plan = dp_test_plan(
    dp_test_spec(files(["p"]), [
      dp_test_mapping("move", "target", "p", "archive"),
      dp_test_mapping("copy", "target", "p", "p/child"),
    ]),
  )
  assert_eq(plan.status, "ready")
  assert_eq(plan.operations[0].kind, "move")
  assert_eq(plan.operations[1].kind, "mkdir")
  assert_eq(plan.operations[2].from, "archive")
}

///|
test "delivery planner resolves mixed mkdir move cycles" {
  let plan = dp_test_plan(
    dp_test_spec(files(["a", "p"]), [
      dp_test_mapping("move", "target", "a", "p/x"),
      dp_test_mapping("move", "target", "p", "a"),
    ]),
  )
  assert_eq(plan.status, "ready")
  assert_eq(plan.temporary_paths.length(), 1)
  assert_eq(plan.operations.length(), 4)
}

///|
test "delivery planner case-only moves use a temporary file" {
  let plan = dp_test_plan(
    dp_test_spec(files(["Readme"]), [
      dp_test_mapping("move", "target", "Readme", "README"),
    ]),
  )
  assert_eq(plan.status, "ready")
  assert_eq(plan.operations.length(), 2)
  assert_eq(plan.temporary_paths.length(), 1)
}

///|
test "delivery planner permits repeated copies but rejects repeated moves" {
  let spec = dp_test_spec(files(["a"]), [
    dp_test_mapping("copy", "target", "a", "b"),
    dp_test_mapping("copy", "target", "a", "c"),
    dp_test_mapping("move", "target", "a", "d"),
  ])
  assert_eq(dp_test_plan(spec).status, "ready")
  let bad = {
    ..spec,
    mappings: [
      dp_test_mapping("move", "target", "a", "b"),
      dp_test_mapping("move", "target", "a", "c"),
    ],
  }
  let plan = dp_test_plan(bad)
  assert_eq(plan.status, "blocked")
  assert_eq(plan.operations.length(), 0)
}

///|
test "delivery planner blocks missing sources and stationary occupants" {
  for
    mapping in [
      dp_test_mapping("copy", "target", "missing", "c"),
      dp_test_mapping("copy", "target", "a", "b"),
    ] {
    let plan = dp_test_plan(dp_test_spec(files(["a", "b"]), [mapping]))
    assert_eq(plan.status, "blocked")
    assert_eq(plan.operations.length(), 0)
    assert_eq(plan.diagnostics[0].step, -1)
  }
}

///|
test "delivery planner sources use exact paths and readonly roots cannot move" {
  let source : @moonportcheck.DeliveryTree = {
    id: "linux",
    snapshot: snapshot_of(files(["A", "a", "CON"]), [], []),
  }
  let base = dp_test_spec([], [])
  let good = {
    ..base,
    sources: [source],
    mappings: [
      dp_test_mapping("copy", "linux", "A", "one"),
      dp_test_mapping("copy", "linux", "a", "two"),
      dp_test_mapping("copy", "linux", "CON", "three"),
    ],
  }
  assert_eq(dp_test_plan(good).status, "ready")
  let bad = {
    ..good,
    mappings: [dp_test_mapping("move", "linux", "A", "one")],
  }
  assert_eq(dp_test_plan(bad).status, "blocked")
}

///|
test "delivery planner incomplete and scoped trees never emit operations" {
  let base = dp_test_spec([], [])
  let source : @moonportcheck.DeliveryTree = {
    id: "partial",
    snapshot: snapshot_of(
      files(["a"]),
      [{ code: "SCAN_IO_ERROR", path: ".", message: "denied", }],
      [],
    ),
  }
  let plan = dp_test_plan({
    ..base,
    sources: [source],
    mappings: [dp_test_mapping("copy", "partial", "a", "a")],
  })
  assert_eq(plan.status, "incomplete")
  assert_eq(plan.operations.length(), 0)
  let scoped = {
    ..base,
    sources: [{ id: "scoped", snapshot: snapshot_of([], [], ["ignored/**"]), }],
  }
  assert_eq(dp_test_plan(scoped).status, "incomplete")
}

///|
test "delivery planner directory copies preserve empty directories and root contents" {
  let base = dp_test_spec([], [])
  let source : @moonportcheck.DeliveryTree = {
    id: "src",
    snapshot: snapshot_of(
      [
        snap_directory("tree"),
        snap_directory("tree/empty"),
        snap_file("tree/a"),
      ],
      [],
      [],
    ),
  }
  let plan = dp_test_plan({
    ..base,
    sources: [source],
    mappings: [dp_test_mapping("copy", "src", "tree", "out")],
  })
  assert_eq(plan.status, "ready")
  assert_true(
    plan.operations.any(op => op.kind == "mkdir" && op.to == "out/empty"),
  )
  assert_true(plan.operations.any(op => op.kind == "copy" && op.to == "out/a"))
  let root = dp_test_plan({
    ..base,
    sources: [source],
    mappings: [dp_test_mapping("copy", "src", "", "")],
  })
  assert_eq(root.status, "ready")
  assert_true(
    root.operations.any(op => op.kind == "mkdir" && op.to == "tree/empty"),
  )
}

///|
test "delivery planner independent replay accepts identity and dependency scenarios" {
  let scenarios = [
    dp_test_spec(files(["a", "b"]), [
      dp_test_mapping("move", "target", "a", "b"),
      dp_test_mapping("move", "target", "b", "a"),
      dp_test_mapping("copy", "target", "b", "copy"),
    ]),
    dp_test_spec(files(["a", "p"]), [
      dp_test_mapping("move", "target", "a", "p/x"),
      dp_test_mapping("move", "target", "p", "a"),
    ]),
    dp_test_spec(files(["Readme"]), [
      dp_test_mapping("move", "target", "Readme", "README"),
    ]),
  ]
  for spec in scenarios {
    let plan = dp_test_plan(spec)
    assert_eq(plan.status, "ready")
    let audit = @moonportcheck.audit_delivery_plan(spec, plan)
    assert_true(
      audit.valid,
      msg=@moonportcheck.render_delivery_audit_json(audit),
    )
  }
}

///|
test "delivery planner reordering mappings retains the same canonical plan" {
  let base = dp_test_spec(files(["a", "b"]), [
    dp_test_mapping("move", "target", "a", "b"),
    dp_test_mapping("move", "target", "b", "a"),
  ])
  let reordered = { ..base, mappings: [base.mappings[1], base.mappings[0]], }
  assert_eq(
    @moonportcheck.render_delivery_plan_json(dp_test_plan(base)),
    @moonportcheck.render_delivery_plan_json(dp_test_plan(reordered)),
  )
}

///|
test "delivery planner scales to ten thousand chain mappings" {
  let entries : Array[@moonportcheck.PathEntry] = []
  let mappings : Array[@moonportcheck.DeliveryMapping] = []
  for i in 0..<10000 {
    let from = "f" + i.to_string()
    entries.push(snap_file(from))
    mappings.push(
      dp_test_mapping("move", "target", from, "f" + (i + 1).to_string()),
    )
  }
  let plan = dp_test_plan(dp_test_spec(entries, mappings))
  assert_eq(plan.status, "ready")
  assert_eq(plan.operations.length(), 10000)
  assert_eq(plan.temporary_paths.length(), 0)
  assert_eq(plan.operations[0].from, "f9999")
  assert_eq(plan.operations[9999].from, "f0")
}

///|
test "delivery planner scales to ten thousand mappings across disjoint cycles" {
  let entries : Array[@moonportcheck.PathEntry] = []
  let mappings : Array[@moonportcheck.DeliveryMapping] = []
  for i in 0..<10000 {
    let from = "f" + i.to_string()
    let to = "f" + (if i % 4 == 3 { i - 3 } else { i + 1 }).to_string()
    entries.push(snap_file(from))
    mappings.push(dp_test_mapping("move", "target", from, to))
  }
  let plan = dp_test_plan(dp_test_spec(entries, mappings))
  assert_eq(plan.status, "ready")
  assert_eq(plan.operations.length(), 12500)
  assert_eq(plan.temporary_paths.length(), 2500)
}
