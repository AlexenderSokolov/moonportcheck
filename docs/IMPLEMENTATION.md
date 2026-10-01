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
