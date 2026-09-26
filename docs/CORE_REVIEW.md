# Independent core and acceptance review

Date: 2026-09-26. Reviewer: independent review subagent.

## Result

No actionable defects were found in the reviewed core, bridge, or acceptance
scripts. This is a bounded review, not a claim that all possible filesystem
behaviors or input sizes have been verified.

## Core and bridge

Read `docs/IMPLEMENTATION.md`, `audit.mbt`, `model.mbt`, `manifest.mbt`,
`report.mbt`, `src/bridge/bridge.mbt`, and their existing tests. Checked:

- Single-path validation, ASCII-only case folding, reserved names and extension
  forms, implicit-directory indexing, exact duplicate counts, and grouped
  rather than pairwise conflict output.
- Occurrences semantics: single-path/name findings and duplicate findings count
  input entries with that exact path; case/kind conflict groups count distinct
  prefix spellings, including implicit directory prefixes.
- Invalid structural paths remaining findings while being excluded from the
  hierarchy index; backslashes remaining literal name characters.
- Deterministic ordinal sorting, quoted paths, input/schema errors, and scan
  completeness taking precedence over portability findings in the exit code.

Ran targeted assertions against the current compiled
`_build/js/release/build/src/bridge/bridge.js`, without rerunning the full suite:

- Literal `bad\name` alongside `bad/name`: one invalid-character finding and
  no invented hierarchy conflict.
- Differently cased implicit directory prefixes with distinct leaf files:
  one grouped prefix collision.
- Invalid `a/../b`, `a//b`, and `a/` alongside the file `a`: structural findings
  without an invented file/directory conflict.
- File `a` and explicit directory `A`: case and kind conflicts.
- A leading Unicode BOM within a filename: preserved as a valid name.
- Twenty deterministic permutations of a mixed fixture: identical reports.
- `CON.txt` plus a scan I/O issue: exit 3, `complete: false`, both findings
  retained.
- Both unpaired high and low surrogate JSON escapes: input errors, exit 2.

All these targeted assertions passed. An earlier `dist/bridge.js` still held
the initial stub during the first read; this was reported immediately to the
implementer and was not used for the targeted assertions. The implementer
subsequently reported that the final build had updated the CLI artifact.

## Acceptance scripts

Read `scripts/acceptance.mjs`, `scripts/parity.mjs`, `scripts/bench.mjs`, and
`scripts/consumer-smoke.mjs`; also inspected the acceptance/check wrappers and
the parity fixture program to verify the calling context.

- Acceptance stops on a nonzero child status or signal and retains step logs.
  Its evidence distinguishes uncommitted source state, hosted CI not run, and
  public release not published. Source hashes and the toolchain lock are
  recorded separately from the test logs.
- Parity requires successful execution of both targets, byte-identical output,
  exactly 23 parsed reports, reversed-input agreement, and representative
  semantic assertions. Empty or stub output cannot satisfy these checks.
- The benchmark runs each 100,000-entry case in a separate process, checks
  completeness and entry count, and checks 200 duplicate groups with exact
  counts plus 100 case-collision groups. Timing and memory are accurately
  described as observations of the bridge path and process, not guarantees.
- The consumer smoke uses a separate module and workspace importing the public
  library, compares parsed and directly constructed entries, and checks the
  actual diagnostic. The copied CLI runs in its own directory with only its
  copied runtime files, PATH containing only Node's directory, and MOON_HOME
  removed; it checks passing/failing manifests and the version. This verifies
  standalone packaging in a separate directory on the current host, not a new
  VM. Its evidence correctly calls this a local workspace dependency and copied
  CLI check; it does not claim registry installation or publication.

No false-success path was identified under the documented wrapper invocation.
The acceptance scripts were reviewed statically in this pass; they were not
executed by this reviewer because another agent was completing the toolchain
bundle. Full Windows/Linux acceptance, final source inventory, and any later
public CI or Mooncakes checks must be established by their own recorded runs.

## Review boundary

No production files or tests were changed. Only this report was added. The
review did not expand the agreed profile to Unicode case equivalence,
normalization, destination state, long-path handling, or automatic repair.
