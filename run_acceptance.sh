#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
source scripts/toolchain.sh
node scripts/acceptance.mjs
