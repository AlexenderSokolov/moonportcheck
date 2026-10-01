# MoonPortCheck 0.1.0 implementation contract

Historical v0.1 contract. The later approved V02_PLAN.md authorizes the GitHub
repository, commits, pushes, continuous PR and history-preserving merge. The
original external-action boundary below describes the earlier implementation.

Approved scope: pure MoonBit portability library plus Node.js 24 CLI; profile
`portable-windows-v1`. Independent project. No remote creation, commit, push,
publication or application submission is authorized in this implementation turn.

## Shared interfaces

The public root package exports EntryKind { File; Directory }, PathEntry
{ path: String; kind: EntryKind }, parse_manifest(String) -> Result[Array[PathEntry], InputError],
audit(Array[PathEntry]) -> Report, render_json(Report) -> String,
render_text(Report) -> String. Reports have deterministic diagnostics and counts.

The JS-only package src/bridge exports run_request(String) -> String. It accepts
a JSON request and returns a JSON response `{ "exit_code": Int, "output": String }`.
The host prints `output` followed by one newline to stdout and uses exit_code.

Requests (format is always `text` or `json`):

- `{mode:"check", format, manifest_text: String}`. UTF-8 decoding is host-side;
  JSON parsing, schema validation, audit, formatting and status are MoonBit.
- `{mode:"scan", format, entries:[{path:String,kind:"file"|"directory"}],
  scan_issues:[{code:String,path:String,message:String}]}`.
- `{mode:"error", format, exit_code:2|3, code:String, message:String}` for host
  argument, decoding and I/O errors. Errors get structured output as well.

The host implements strict arguments `scan ROOT` or `check MANIFEST`, optional
`--format text|json`, and standalone `--help` / `--version`. No implicit ignores,
no writes to the input tree. A trailing slash is not used in manifest paths.

Host scan(root) returns entries and scan_issues; lstat root and every child,
never follow symlinks or junctions. Root is not a PathEntry. Hidden entries
are included. Only metadata is read. Readdir raw filename bytes must decode
with fatal UTF-8 (also reject unpaired surrogates). Unrepresentable names,
links, other types or failures make the scan incomplete. Error messages must
not include host-specific absolute roots or stack traces in normal reports.
Do not normalize POSIX backslashes into separators.

Scan codes: SCAN_IO_ERROR, SCAN_LINK_SKIPPED, SCAN_TYPE_UNSUPPORTED,
SCAN_NAME_ENCODING. Input codes: ARGUMENT_ERROR, INPUT_ENCODING, INPUT_SCHEMA,
INPUT_JSON, INPUT_IO_ERROR. Invalid paths in valid entries are audit findings.

Report shape: schema_version=1, profile, source=`manifest`|`scan`, complete,
summary {entries,files,directories,diagnostic_groups,scan_issues},
diagnostics [{code,severity,paths,occurrences,message}], limitations[String].
Diagnostics sort by (code, paths); paths sort ordinally and are unique within
a group. Duplicate diagnostics carry exact occurrence count. Timestamps and
absolute scan roots are absent. Text quotes paths safely, including controls.

Exit: 3 if scan incomplete or I/O failed; otherwise 2 for malformed input or
arguments; otherwise 1 for audit findings; otherwise 0. Errors use an error
envelope rather than pretending a report was produced. Pure audit concerns
the supplied list only; CLI adds source and scan completeness.

Rules: PATH_EMPTY, PATH_ABSOLUTE, PATH_DRIVE, PATH_EMPTY_COMPONENT,
PATH_DOT_COMPONENT, NAME_INVALID_CHAR, NAME_RESERVED, NAME_TRAILING_DOT_SPACE,
PATH_DUPLICATE, PATH_CASE_COLLISION, PATH_KIND_CONFLICT.
ASCII folding only. Reserved stems before the first dot match Microsoft's
CON/PRN/AUX/NUL/COM1-9/LPT1-9 including superscript 1/2/3. Use a prefix index
for implicit directories, grouping collisions instead of pairwise output.
Invalid structural paths still get single-path diagnostics but are excluded
from hierarchy indexing. Duplicate full paths are counted independently.

## Build contract

MoonBit v0.10.14, project-local toolchain. Core tests: JS and wasm-gc.
src/bridge builds ESM to dist/bridge.js. bin/moonportcheck.mjs imports that file.
run_build.ps1/sh builds and copies it. No npm runtime dependencies.
run_check.ps1/sh checks toolchain, format, build, both core test targets,
Node tests and cross-target report parity. Artifacts retained; no bulk cleanup.

## Completion evidence

Rule fixtures, failing examples, Windows/Linux CLI tests, shuffled-input and
cross-target parity, 100k ordinary and conflict-heavy path benchmarks,
clean consumer and packaged CLI validation. Public CI and Mooncakes status
remain pending until authorized external release. The project has an independent
Git repository. Before its first commit, source_commit is null; source file
hashes identify the tested uncommitted snapshot without inventing a release SHA.

## M06 additions (v0.2, exclusion scope)

New root API in `scope.mbt`: `parse_scope(Array[String]) ->
Result[ExclusionScope, InputError]`, `entry_excluded(ExclusionScope, PathEntry)
-> Bool`, `effective_scope_patterns(ExclusionScope) -> Array[String]` and
`audit_with_exclusions(Array[PathEntry], AuditOptions, ExclusionScope) ->
DetailedReport`. `ExclusionScope` is opaque; it wraps the deduplicated, ordinal
patterns and their compiled `PathPattern`s. `parse_scope` rejects invalid
patterns with `PATTERN_INVALID`. `audit_with_exclusions` filters retained
entries through the existing `audit_with_options`, then records the scope
patterns, the count of excluded known inputs, and the top-most pruned
directories (a directory whose ancestor is already excluded is subsumed, so a
scan and an equivalent manifest yield identical scope/diagnostics/summary/
pruned_directories). Nothing invents counts for unenumerated subtrees.

New bridge request modes in `src/bridge/bridge.mbt`:

- `{mode:"scope", format:"json", config_text?:"…JSON…", cli_exclude?:[String]}`.
  Parses the versioned config (schema_version must be 1, unknown fields fail
  with `INPUT_CONFIG`), merges CLI exclusions, validates every pattern, and
  returns `{"patterns":[...]}`. The host calls this once before a scan/check to
  fail fast on config errors and to obtain the canonical pattern list.
- `{mode:"excluded", format:"json", patterns:[String], path:String,
  kind:"file"|"directory"}` returns `"true"`/`"false"` using the same MoonBit
  matcher, so the Node host never reimplements glob semantics.
- `check` and `scan` accept an optional `exclude_patterns:[String]`; the
  effective scope is applied inside MoonBit and flows into the schema 2 fields.

CLI: `--config FILE` (at most once) and repeatable `--exclude PATTERN` are valid
for `scan` and `check`. A missing/undecodable config maps to `INPUT_IO_ERROR`
(exit 3) / `INPUT_ENCODING` (exit 2), the same as a manifest. The host scan
prunes a directory when the MoonBit predicate matches it as a directory: the
directory is still recorded as an entry but its subtree is not enumerated;
excluded entries never become scan issues. No `.gitignore` is ever read
implicitly.

## M07 additions (v0.2, snapshot model)

New root API in `snapshot.mbt`: `Snapshot`, `build_snapshot(Array[PathEntry],
Array[ScanIssue], Array[String]) -> Result[Snapshot, InputError]`,
`parse_snapshot(String) -> Result[Snapshot, InputError]` and
`render_snapshot_json(Snapshot) -> String`. A `Snapshot` stores only the profile,
completeness, the canonical scope, the unique sorted entries, and the scan
issues of a scan — never content, timestamps or host absolute paths. `parse_*`
and `render_*` round-trip exactly: the serializer emits a stable field order,
`parse_snapshot` requires canonical input (entries strictly sorted and unique,
only known fields, valid patterns), and corrupted or non-canonical documents are
rejected with `INPUT_SCHEMA` / `PATTERN_INVALID`. Building a snapshot
deduplicates identical entries, rejects a path with conflicting kinds, and
normalizes the scope; a snapshot with no scan issues is `complete`. `check`
continues to accept the original array manifests; snapshot-aware check and the
`snapshot` bridge/CLI command arrive in M08 (per the plan, the snapshot document
does not replace `parse_manifest`). `cmd/parity` gains two snapshot fixtures
(build-render and parse-round-trip render) so both execution backends stay
byte-identical.

## M08 additions (v0.2, snapshot command and snapshot-aware check)

`snapshot.mbt` gains `audit_snapshot(Snapshot, Array[String]) ->
Result[DetailedReport, InputError]`: it checks a snapshot for the active profile,
inheriting the snapshot's canonical `scope` and applying extra exclusions on top
(extra patterns can only shrink the checked set). A foreign `profile` is
rejected with `INPUT_SCHEMA`. The snapshot's stored `scan_issues` are carried
unchanged, so an incomplete snapshot always produces an incomplete report;
`source` is `"snapshot"`.

`src/bridge` adds a `snapshot` mode
(`{mode:"snapshot", format, entries, scan_issues, exclude_patterns}`):
`build_snapshot(entries, issues, effective_scope)` serialized via
`render_snapshot_json`, exit 0 when `complete` and 3 when not. The `check` mode
now classifies its input by the parsed JSON value: an array is the original
manifest path, an object is parsed as a snapshot and audited via
`audit_snapshot` (with `exclude_patterns` as the shrink-only extras), anything
else is an `INPUT_SCHEMA` error. The shared `scan_issues` field is parsed by one
helper used by both `scan` and `snapshot` modes. `lib/host.mjs`
`parseArguments` accepts `snapshot` (target required; `--format` rejected
because the document is always JSON; `--config`/`--exclude` allowed), and the
bin wires `moonportcheck snapshot ROOT` to scan + `snapshot` mode, writing the
snapshot document to stdout.

`cmd/parity` gains one `audit_snapshot` fixture so `render_detailed_json` of a
snapshot-audited report is byte-identical across js/wasm-gc (68 reports total).

## M09 additions (v0.2, snapshot diff core and report)

New root API in `diff.mbt`: `DiffKind` (`Added`/`Removed`/`KindChanged`/
`CaseChanged`), `SnapshotChange`, `SnapshotDiff` and
`diff_snapshots(Snapshot, Snapshot) -> Result[SnapshotDiff, InputError]` plus
`render_snapshot_diff_json(SnapshotDiff) -> String`. A diff requires the two
snapshots to have identical canonical scopes (`INPUT_SCHEMA` otherwise). Entries
are matched by exact path first (same path with a different kind becomes a
`kind` change); the remaining entries are then compared by ASCII folding, and a
`case` change is reported only for a one-to-one fold whose before and after
entries have the same kind. Renames or content changes are never inferred.
Changes sort by kind rank (`added`, `removed`, `kind`, `case`) then path ordinal,
and the serialized document is a stable `{"format":"moonportcheck-diff",
"version":1,"complete":bool,"changes":[...]}`; `complete` is the conjunction of
the two inputs' completeness. `cmd/parity` gains one diff fixture (69 reports
total). The `diff` bridge mode and CLI arrive in M10.

## M10 additions (v0.2, diff command and exit semantics)

`diff.mbt` gains `render_snapshot_diff_text(SnapshotDiff) -> String`, a stable
human-readable rendering that flags an incomplete input on the first line
(`INCOMPLETE: the input snapshot is incomplete; ...`). `src/bridge` adds a
`diff` mode
(`{mode:"diff", format, before_text, after_text}`): both inputs are parsed as
snapshots, compared with `diff_snapshots`, and rendered as the JSON document or
the text rendering per `format`. Exit codes: `2` for a malformed document or
mismatched scopes, `3` when either input is incomplete, `1` when there are
changes and `0` otherwise. `lib/host.mjs` `parseArguments` accepts `diff`
(exactly two snapshot paths; `--config`/`--exclude` rejected; `--format`
`text`/`json` allowed) and the bin wires
`moonportcheck diff BEFORE.json AFTER.json`. `cmd/parity` count stays 69 because
the text rendering derives from the same diff structure.

## M11 additions (v0.2, baseline model and classification core)

New root `baseline.mbt`: `BaselineStatus` (`new`/`existing`/`worsened`/
`resolved`), `BaselineGroup`, `Baseline`, `BaselineChange`, `BaselineDiff`,
`rules_version()`, `build_baseline(DetailedReport)`, `diff_with_baseline` and
the `render_baseline_json` / `render_baseline_diff_json` /
`render_baseline_diff_text` serializers.

`build_baseline` accepts only a complete schema 2 audit report (rejecting
others with `INPUT_SCHEMA` or `INPUT_INCOMPLETE`) and records the active profile,
the `rules_version()` string and the report's effective scan scope. The
classification associates groups by `code + "\u0000" + anchor` (rule code plus
stable path anchor). A baseline group with no matching report group is
`resolved`; a matching group whose member multiset gained a fresh
path/kind member or a higher count is `worsened`; otherwise it is `existing`
(including groups that lost members). Report groups absent from the baseline are
`new`. Changes sort by status rank (`new`, `worsened`, `existing`, `resolved`)
then code and anchor. `cmd/parity` gains a baseline and a baseline-diff fixture
(71 reports at M11).

## M12: baseline create and scan --baseline --fail-on

`parse_baseline(String)` returns a `Baseline` (from `baseline.mbt`) from a
document produced by `render_baseline_json`; it is strict about the format and
version fields, rejects unknown fields, and normalizes the bound effective
scope the same way as the report. `parse_detailed_report(String)` (from
`detailed.mbt`) reads the full schema 2 report back (summary, diagnostics with
members/source_examples, scan_issues, scope, exclusions, pruning); it validates
integers and booleans strictly and rejects unknown fields so a newer report can
never be silently downgraded. `baseline create` is that parse+rebuild round
trip: passing `render_detailed_json(report)` through
`build_baseline ∘ parse_detailed_report` regenerates the identical baseline
document (asserted byte-for-byte in the parity fixture).

The bridge adds a `baseline` mode (report text in, fixed baseline JSON out,
exit 0; non-schema-2, incomplete or malformed input exits 2) and optional
baseline gating for `scan`. A scan request carrying `baseline_text` parses the
baseline, verifies the bound profile, rules version and effective scope against
the current scan (any mismatch exits 2), and classifies via `diff_with_baseline`.
Under `fail_on` the exit code is 1 only for `new` or `worsened` groups; the
default judges the whole problem set (any findings exit 1). An incomplete scan
always exits 3 before baseline policy is consulted — a baseline never exempts a
failed scan.

`baseline create REPORT.json` (host: `baseline` mode, subcommand `create`)
rejects config, exclusions and `--format` since the document is fixed JSON.
`scan ROOT --baseline BASELINE.json --fail-on new` adds `baseline_text` (and
`fail_on`) to the scan request; `--fail-on` only accepts `new`, is only valid
for scan, and requires `--baseline`.

## M13: Markdown snapshot diffs and SARIF 2.1.0 check reports

Two new core renderers plus CLI wiring: `render_snapshot_diff_markdown` in
`diff.mbt` and `render_check_sarif` in a new `sarif.mbt`.

`render_snapshot_diff_markdown(SnapshotDiff)` renders a `# MoonPortCheck diff`
document: a compact `INCOMPLETE` blockquote when the diff is not complete,
otherwise a `| Kind | Path | Details |` table with one row per change
(`added`/`removed`/`kind`/`case`), paths wrapped in backticks, and cell
escaping for pipes and newlines so a hostile path cannot break the table
(`md_cell`). `--format markdown` is accepted only by `diff` in `lib/host.mjs`.

`render_check_sarif(DetailedReport)` emits a SARIF 2.1.0 document whose driver
is `MoonPortCheck` (version 0.2.0-dev, informationUri the public repository),
one result per diagnostic and per scan issue, and a run invocation whose
`executionSuccessful` equals `report.complete` (scan issues become `note`-level
results). Every location carries only an artifact URI — the model has no source
line numbers, so no region and no source line is ever fabricated, and the URI
is percent-encoded from the path's UTF-8 bytes (ASCII letters/digits and
`-._~/` stay literal). Limitations render as `toolExecutionNotifications`.
`--report sarif` is accepted only by `check` and sets `report:"sarif"`; the
bridge's `report_output` routes to the SARIF renderer for check (manifest,
snapshot and scan inputs alike) while `scan --baseline` keeps its text/json
`baseline_response` gating. The parity fixture (81 lines) asserts the markdown
and SARIF outputs are byte-identical between the js and wasm-gc targets.

## M14: Markdown reports for scan/check and CI report artifacts

`render_detailed_markdown(DetailedReport)` in `detailed.mbt` renders a `#
MoonPortCheck report` document: a status line (`INCOMPLETE`/`PASS (covered
rules only)`/`FINDINGS`), scope and exclusion summary, a `## Findings` table
(Code/Paths/Occurrences/Message), a `## Scan issues` table and `## Coverage
limits` — the same conclusions as text/JSON/SARIF. Paths, codes and messages
pass through `md_cell` so a hostile name cannot break a table cell. The bridge
routes `format="markdown"` through `render_detailed_markdown` for check,
manifest/scan (`report_response` and `baseline_response` alike);
`lib/host.mjs` now accepts `--format markdown` for `check`/`scan`/`diff`
(never `rules`/`explain`, and `--report sarif` plus `--format markdown` is
rejected as conflicting). `scripts/format-matrix.mjs` is a new gate in
`run_check`/`run_check.sh`: for the same input every format must exit with the
same code, and the SARIF result rule ids equal the JSON diagnostic codes.

The workflow gains a report sample (`scripts/ci-report.mjs`): it scans a small
cross-platform fixture, writes `artifacts/reports/{scan.json,scan.txt,scan.md,
check.sarif,snapshot.json,diff.md,summary.md}`, uploads them as the `reports-*
` artifact, and appends a Markdown summary to `$GITHUB_STEP_SUMMARY`. This is a
report-obtainability sample; it does not claim that GitHub Code Scanning
accepted the SARIF file.

## M15: property tests, scale benchmark and the LOC gate

No product code changes; this milestone hardens verification. `scripts/
property.mjs` (deterministic mulberry32 seed 0xC0FFEE, 60 random manifests)
asserts four invariants against the built bridge: (1) permuting the input
entries leaves the rendered report byte-identical; (2) widening the exclusion
scope never adds findings and never lowers `excluded_entries`; (3) re-auditing
and report/baseline parse+rebuild round trips are stable; (4) a baseline built
from a manifest, re-scanning the same manifest with `fail_on: new`, exits 0
(no group comes back as new). `scripts/bench.mjs` now runs five cases in
separate processes — ordinary 100k, grouped conflicts 100k (300 groups with
exact duplicate counts), 40-level deep paths (2000), a 1500-character shared
prefix (2000) and a single 10k-copy duplicate group — and records elapsed_ms,
peak RSS and report bytes to `artifacts/benchmark.json`. Both scripts run in
`run_check`/`run_check.sh` alongside parity and format-matrix, and the code
statistics gate is now a hard floor: `node scripts/code-stats.mjs --min 3000`.
