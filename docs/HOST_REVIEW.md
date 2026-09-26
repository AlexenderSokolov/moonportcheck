# Host adapter review

Reviewed independently from its author on 2026-09-26: `lib/host.mjs`,
`bin/moonportcheck.mjs`, and the host/CLI regression tests.

## Result

No release-blocking issue was identified in the inspected adapter code.
This is a bounded source review, not a claim that the complete CLI or public CI
has passed. The actual MoonBit response construction is outside this review.

## Evidence checked

- Directory traversal checks `lstat` on the supplied root and every discovered
  child. Symbolic links and Windows junctions become `SCAN_LINK_SKIPPED` and are
  excluded from traversal. Hidden entries and empty directories are retained.
- Directory names are requested as raw buffers, decoded with fatal UTF-8,
  and checked for unpaired surrogates. Leading BOMs and POSIX backslashes are
  preserved. Unrepresentable names become scan issues rather than disappearing.
- Metadata and directory-enumeration failures preserve other discovered entries
  and produce `SCAN_IO_ERROR`. Native exception messages and absolute roots are
  not copied into reports. Scanning never calls `readFile` for tree entries.
- Argument errors are classified before filesystem access; a valid requested
  JSON format is retained even when other arguments are malformed. Manifest
  decoding failures use exit 2, while manifest read failures use exit 3.
- The CLI forwards scan completeness to the MoonBit bridge and uses the returned
  exit code. It sets `process.exitCode` after writing rather than aborting pending
  stdout writes, preserving redirected JSON output.

Previously executed on local Ubuntu with project-isolated Node v24.15.0:
`node --test tests/host.test.mjs` passed all 9 tests with no skips, including real
POSIX invalid UTF-8 names and links. Tests were not repeated for this review.

## Boundary

The adapter explicitly assumes a static, trusted delivery tree. `lstat` followed
by directory enumeration is not atomic, so this implementation does not promise
to resist adversarial filesystem changes between those operations. Complete
CLI exit-code behavior still requires the integrated bridge and end-to-end run.
