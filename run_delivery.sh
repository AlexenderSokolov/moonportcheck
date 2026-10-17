#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source scripts/toolchain.sh
bash run_build.sh
node --test tests/delivery.test.mjs
node scripts/delivery-parity.mjs
node scripts/delivery-verification.mjs
node scripts/delivery-cases.mjs
node scripts/delivery-fs.mjs
