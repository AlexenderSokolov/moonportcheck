#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$root/scripts/toolchain.sh"
cd "$root"
node scripts/toolchain.mjs version
node scripts/api-check.mjs
node --test scripts/*.test.mjs
moon fmt --check
moon check --target js --deny-warn
moon check --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target wasm-gc --deny-warn
bash "$root/run_build.sh"
node --test tests/*.test.mjs
node scripts/parity.mjs
node scripts/format-matrix.mjs
node scripts/property.mjs
node scripts/bench.mjs
node scripts/code-stats.mjs --min 3000
