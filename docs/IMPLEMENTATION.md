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
