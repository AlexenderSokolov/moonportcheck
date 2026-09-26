#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
source ./scripts/toolchain.sh
bash ./run_build.sh
node ./scripts/demo.mjs
