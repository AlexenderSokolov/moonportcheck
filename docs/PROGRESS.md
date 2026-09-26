# MoonPortCheck implementation progress

This is the historical v0.1 implementation record. The user subsequently
authorized the v0.2 GitHub workflow on 2026-09-26; current authorization and
progress are recorded in V02_PLAN.md and V02_PROGRESS.md.

- Approved plan: user message dated 2026-09-26; goal is local v0.1.0 candidate.
- Initial state: project absent; parent has existing untracked moontrack and
  moonsplit directories. They remain untouched.
- Execution: separate toolchain and filesystem/CLI work may run alongside
  the core, sharing the contract in IMPLEMENTATION.md. No bulk deletions.
- Verification: write meaningful behavior tests first; retain acceptance
  artifacts; independent whole-project review before completion.
- Decisions: JSON array manifests; no automatic path normalization; pure core
  separated from scan completeness. New project isolates toolchain and build.
- External publication and a source commit are not yet authorized. Do not
  manufacture a release SHA or claim hosted CI ran.

## Completed on 2026-09-26

- Implemented the pure MoonBit model, manifest parsing, path and prefix rules,
  grouped deterministic diagnostics, JSON/text rendering, and JS bridge.
- Implemented the Node 24 host and CLI with strict UTF-8, hidden entries,
  metadata-only scans, link/junction exclusion, and incomplete-scan precedence.
- Added separate MoonBit v0.10.14 toolchains for Windows/Linux, version/hash
  locks, PowerShell/Bash entry points, public API files, and two-OS CI config.
- Added three executable demos, 100k-input benchmarks, an independent library
  consumer, and a copied CLI test without the compiler on PATH.
- Full Windows acceptance: 21 core tests on each target; Node 18 pass with
  2 POSIX-only skips; all demo, parity, benchmark, and consumer steps passed.
- Full Ubuntu WSL acceptance: 21 core tests on each target; Node 20 pass with
  no skips, including real bad names and invalid UTF-8; all other steps passed.
- Both platforms tested the same source manifest hash, recorded in ACCEPTANCE.md.
  Core/bridge and host reviews found no actionable defects. No remote changes,
  publication, source commits, deletions, or changes to other works were made.
- After these runs, only ACCEPTANCE.md and this progress record were finalized.

## Implementation decisions resolved by evidence

- Current MoonBit String.Compare is length-first; reports explicitly compare
  UTF-16 code units to provide ordinal lexicographic ordering.
- `moon info --target js` still has canonical Wasm output, so the isolated
  toolchain also bundles the Wasm standard library. Both OS runs succeeded.
- Historical compiler archive endpoints were unavailable; content-pin the
  verified official archives and retain caches rather than silently upgrading.
- First local Git commit and remote release remain pending; evidence uses null
  source_commit plus file hashes instead of a borrowed or invented commit SHA.

Detailed outcomes and retained log locations: [ACCEPTANCE.md](ACCEPTANCE.md).
