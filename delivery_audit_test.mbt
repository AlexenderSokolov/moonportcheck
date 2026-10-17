///|
fn da_snapshot(
  entries : Array[@moonportcheck.PathEntry],
) -> @moonportcheck.Snapshot raise {
  match @moonportcheck.build_snapshot(entries, [], []) {
    Ok(s) => s
    Err(e) => fail(e.message)
  }
}

///|
fn da_file(p : String) -> @moonportcheck.PathEntry {
  { path: p, kind: @moonportcheck.File, }
}

///|
fn da_spec() -> @moonportcheck.DeliverySpec raise {
  {
    sources: [
      {
        id: "linux",
        snapshot: da_snapshot([da_file("CON"), da_file("A"), da_file("a")]),
      },
    ],
    target: {
      id: "out",
      snapshot: da_snapshot([da_file("a"), da_file("b"), da_file("keep")]),
    },
    mappings: [
      { mode: "move", source: "out", from: "a", to: "b", },
      { mode: "move", source: "out", from: "b", to: "a", },
      { mode: "copy", source: "linux", from: "CON", to: "safe", },
    ],
  }
}

///|
fn da_op(
  kind : String,
  source : String,
  from : String,
  to : String,
  root : String,
  path : String,
) -> @moonportcheck.DeliveryOperation {
  { kind, source, from, to, origin: { root, path, }, }
}

///|
fn da_plan(
  spec : @moonportcheck.DeliverySpec,
  ops : Array[@moonportcheck.DeliveryOperation],
  temps : Array[String],
) -> @moonportcheck.DeliveryPlan {
  {
    status: "ready",
    basis: @moonportcheck.render_delivery_spec_json(spec),
    operations: ops,
    temporary_paths: temps,
    diagnostics: [],
  }
}

///|
fn da_swap() -> Array[@moonportcheck.DeliveryOperation] {
  [
    da_op("move", "out", "a", ".moonportcheck-stage-1", "out", "a"),
    da_op("move", "out", "b", "a", "out", "b"),
    da_op("move", "out", ".moonportcheck-stage-1", "b", "out", "a"),
    da_op("copy", "linux", "CON", "safe", "linux", "CON"),
  ]
}

///|
test "delivery audit accepts independent plans and alternate legal ordering" {
  let spec = da_spec()
  let ops = da_swap()
  let first = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, ops, [".moonportcheck-stage-1"]),
  )
  assert_true(first.valid)
  assert_eq(first.trace.length(), 4)
  assert_eq(first.final_entries.length(), 4)
  let alternate = [ops[3], ops[0], ops[1], ops[2]]
  let second = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, alternate, [".moonportcheck-stage-1"]),
  )
  assert_true(second.valid)
  @test.assert_eq(first.final_entries, second.final_entries)
}

///|
test "delivery audit detects occupied destination and forged identity at exact step" {
  let spec = da_spec()
  let bad_order = [da_swap()[1]]
  let result = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, bad_order, []),
  )
  assert_false(result.valid)
  assert_eq(result.first_failed_step, 0)
  let bad_identity = [
    da_op("move", "out", "a", ".moonportcheck-stage-1", "out", "b"),
  ]
  let result = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, bad_identity, [".moonportcheck-stage-1"]),
  )
  assert_false(result.valid)
  assert_eq(result.first_failed_step, 0)
}

///|
test "delivery audit detects omitted delivery and temporary leftovers" {
  let spec = da_spec()
  let ops = da_swap()
  for partial in [[ops[0]], [ops[0], ops[1], ops[2]]] {
    let result = @moonportcheck.audit_delivery_plan(
      spec,
      da_plan(spec, partial, [".moonportcheck-stage-1"]),
    )
    assert_false(result.valid)
    assert_eq(result.first_failed_step, -1)
  }
}

///|
test "delivery audit rejects unrelated moves extra mkdir and occupied temp declaration" {
  let spec = da_spec()
  for
    op in [
      da_op("move", "out", "keep", "new", "out", "keep"),
      da_op("mkdir", "", "", "unrelated", "", ""),
      da_op("copy", "linux", "A", "safe", "linux", "A"),
    ] {
    let result = @moonportcheck.audit_delivery_plan(
      spec,
      da_plan(spec, [op], []),
    )
    assert_false(result.valid)
    assert_eq(result.first_failed_step, 0)
  }
  let occupied = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, da_swap(), ["a"]),
  )
  assert_false(occupied.valid)
  assert_eq(occupied.first_failed_step, -1)
}

///|
test "delivery audit checks canonical basis and ready status" {
  let spec = da_spec()
  let good = da_plan(spec, da_swap(), [".moonportcheck-stage-1"])
  let wrong_basis = { ..good, basis: "{}", }
  assert_false(@moonportcheck.audit_delivery_plan(spec, wrong_basis).valid)
  let not_ready = { ..good, status: "blocked", }
  assert_false(@moonportcheck.audit_delivery_plan(spec, not_ready).valid)
}

///|
test "delivery audit permits a file to become parent after move and preserves empty dirs" {
  let spec : @moonportcheck.DeliverySpec = {
    sources: [
      {
        id: "src",
        snapshot: da_snapshot([
          { path: "empty", kind: @moonportcheck.Directory, },
          da_file("p"),
        ]),
      },
    ],
    target: { id: "out", snapshot: da_snapshot([da_file("p")]), },
    mappings: [
      { mode: "move", source: "out", from: "p", to: "saved", },
      { mode: "copy", source: "src", from: "", to: "p", },
    ],
  }
  let operations = [
    da_op("move", "out", "p", "saved", "out", "p"),
    da_op("mkdir", "", "", "p", "", ""),
    da_op("mkdir", "", "", "p/empty", "", ""),
    da_op("copy", "src", "p", "p/p", "src", "p"),
  ]
  let result = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, operations, []),
  )
  assert_true(result.valid)
  assert_eq(result.final_entries.length(), 4)
  let wrong = [operations[1], operations[0], operations[2], operations[3]]
  assert_eq(
    @moonportcheck.audit_delivery_plan(spec, da_plan(spec, wrong, [])).first_failed_step,
    0,
  )
}

///|
test "delivery audit accepts two fresh temporary hops for one identity" {
  let spec = da_spec()
  let operations = [
    da_op("move", "out", "a", ".moonportcheck-stage-1", "out", "a"),
    da_op(
      "move", "out", ".moonportcheck-stage-1", ".moonportcheck-stage-2", "out", "a",
    ),
    da_op("move", "out", "b", "a", "out", "b"),
    da_op("move", "out", ".moonportcheck-stage-2", "b", "out", "a"),
    da_op("copy", "linux", "CON", "safe", "linux", "CON"),
  ]
  assert_true(
    @moonportcheck.audit_delivery_plan(
      spec,
      da_plan(spec, operations, [
        ".moonportcheck-stage-1", ".moonportcheck-stage-2",
      ]),
    ).valid,
  )
}

///|
test "delivery audit supports distinct Linux source casing and rejects readonly Move" {
  let initial = da_spec()
  let mappings : Array[@moonportcheck.DeliveryMapping] = [
    { mode: "copy", source: "linux", from: "A", to: "upper", },
    { mode: "copy", source: "linux", from: "a", to: "lower", },
  ]
  let spec = { ..initial, mappings, }
  let operations = [
    da_op("copy", "linux", "A", "upper", "linux", "A"),
    da_op("copy", "linux", "a", "lower", "linux", "a"),
  ]
  assert_true(
    @moonportcheck.audit_delivery_plan(spec, da_plan(spec, operations, [])).valid,
  )
  let bad = [da_op("move", "linux", "A", "upper", "linux", "A")]
  assert_eq(
    @moonportcheck.audit_delivery_plan(spec, da_plan(spec, bad, [])).first_failed_step,
    0,
  )
  let wrong_case = [da_op("copy", "linux", "a", "upper", "linux", "A")]
  assert_eq(
    @moonportcheck.audit_delivery_plan(spec, da_plan(spec, wrong_case, [])).first_failed_step,
    0,
  )
}

///|
test "delivery audit rejects unknown roots duplicate Moves and occupied final files" {
  let initial = da_spec()
  let cases : Array[Array[@moonportcheck.DeliveryMapping]] = [
    [{ mode: "copy", source: "missing", from: "a", to: "new", }],
    [
      { mode: "move", source: "out", from: "a", to: "x", },
      { mode: "move", source: "out", from: "a", to: "y", },
    ],
    [{ mode: "copy", source: "linux", from: "A", to: "keep", }],
    [{ mode: "move", source: "linux", from: "A", to: "new", }],
  ]
  for mappings in cases {
    let spec : @moonportcheck.DeliverySpec = { ..initial, mappings, }
    let result = @moonportcheck.audit_delivery_plan(spec, da_plan(spec, [], []))
    assert_false(result.valid)
    assert_eq(result.first_failed_step, -1)
  }
}

///|
test "delivery audit validates readiness input completeness and unique root namespaces" {
  let initial = da_spec()
  let duplicate = { ..initial, sources: [initial.target], }
  assert_false(
    @moonportcheck.audit_delivery_plan(duplicate, da_plan(duplicate, [], [])).valid,
  )
  let text = @moonportcheck.render_snapshot_json(initial.target.snapshot)
  let incomplete = match
    @moonportcheck.parse_snapshot(
      text.replace(old="\"complete\":true", new="\"complete\":false"),
    ) {
    Ok(snapshot) => snapshot
    Err(e) => fail(e.message)
  }
  let spec = { ..initial, target: { id: "out", snapshot: incomplete, }, }
  let result = @moonportcheck.audit_delivery_plan(spec, da_plan(spec, [], []))
  assert_false(result.valid)
  assert_eq(result.status, "incomplete")
}

///|
test "delivery audit handles ten thousand independent operations with compact trace" {
  let entries : Array[@moonportcheck.PathEntry] = []
  let mappings : Array[@moonportcheck.DeliveryMapping] = []
  let operations : Array[@moonportcheck.DeliveryOperation] = []
  for i in 0..<10000 {
    let path = "f" + i.to_string()
    entries.push(da_file(path))
    mappings.push({ mode: "copy", source: "src", from: path, to: path, })
    operations.push(da_op("copy", "src", path, path, "src", path))
  }
  let spec : @moonportcheck.DeliverySpec = {
    sources: [{ id: "src", snapshot: da_snapshot(entries), }],
    target: { id: "out", snapshot: da_snapshot([]), },
    mappings,
  }
  let result = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, operations, []),
  )
  assert_true(result.valid)
  assert_eq(result.final_entries.length(), 10000)
  assert_eq(result.trace.length(), 10000)
}

///|
test "delivery audit indexes ten thousand disjoint empty directory mappings" {
  let entries : Array[@moonportcheck.PathEntry] = []
  let mappings : Array[@moonportcheck.DeliveryMapping] = []
  let operations : Array[@moonportcheck.DeliveryOperation] = []
  for i in 0..<10000 {
    let path = "dir" + i.to_string()
    entries.push({ path, kind: @moonportcheck.Directory, })
    mappings.push({ mode: "copy", source: "src", from: path, to: path, })
    operations.push(da_op("mkdir", "", "", path, "", ""))
  }
  let spec : @moonportcheck.DeliverySpec = {
    sources: [{ id: "src", snapshot: da_snapshot(entries), }],
    target: { id: "out", snapshot: da_snapshot([]), },
    mappings,
  }
  let result = @moonportcheck.audit_delivery_plan(
    spec,
    da_plan(spec, operations, []),
  )
  assert_true(result.valid)
  assert_eq(result.final_entries.length(), 10000)
  assert_eq(result.trace.length(), 10000)
}

///|
test "delivery audit permits root and subdirectory Copy into target root" {
  let source : @moonportcheck.DeliveryTree = {
    id: "src",
    snapshot: da_snapshot([
      da_file("sub/a"),
      { path: "sub/empty", kind: @moonportcheck.Directory, },
    ]),
  }
  let target : @moonportcheck.DeliveryTree = {
    id: "out",
    snapshot: da_snapshot([]),
  }
  let root : @moonportcheck.DeliverySpec = {
    sources: [source],
    target,
    mappings: [{ mode: "copy", source: "src", from: "", to: "", }],
  }
  let root_ops = [
    da_op("mkdir", "", "", "sub", "", ""),
    da_op("mkdir", "", "", "sub/empty", "", ""),
    da_op("copy", "src", "sub/a", "sub/a", "src", "sub/a"),
  ]
  assert_true(
    @moonportcheck.audit_delivery_plan(root, da_plan(root, root_ops, [])).valid,
  )
  let sub = {
    ..root,
    mappings: [{ mode: "copy", source: "src", from: "sub", to: "", }],
  }
  let sub_ops = [
    da_op("mkdir", "", "", "empty", "", ""),
    da_op("copy", "src", "sub/a", "a", "src", "sub/a"),
  ]
  assert_true(
    @moonportcheck.audit_delivery_plan(sub, da_plan(sub, sub_ops, [])).valid,
  )
  let bad = {
    ..root,
    mappings: [{ mode: "copy", source: "src", from: "sub/a", to: "", }],
  }
  assert_false(
    @moonportcheck.audit_delivery_plan(bad, da_plan(bad, [], [])).valid,
  )
}

///|
test "delivery audit marks scoped snapshots incomplete" {
  let initial = da_spec()
  let scoped = match @moonportcheck.build_snapshot([], [], ["ignored/**"]) {
    Ok(snapshot) => snapshot
    Err(e) => fail(e.message)
  }
  let spec = { ..initial, target: { id: "out", snapshot: scoped, }, }
  let result = @moonportcheck.audit_delivery_plan(spec, da_plan(spec, [], []))
  assert_false(result.valid)
  assert_eq(result.status, "incomplete")
  assert_eq(result.first_failed_step, -1)
}
