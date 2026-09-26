#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$root/scripts/toolchain.sh"
cd "$root"
moon build --target js --release --deny-warn src/bridge
mkdir -p dist
cp _build/js/release/build/src/bridge/bridge.js dist/bridge.js
