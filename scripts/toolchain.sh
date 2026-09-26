#!/usr/bin/env bash
# Source this file to select the isolated toolchain in the current shell.
set -euo pipefail
moonport_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -ms)" != 'Linux x86_64' ]]; then
  echo 'This script supports Linux x64. On Windows use toolchain.ps1.' >&2
  return 1 2>/dev/null || exit 1
fi
if [[ -x "$moonport_root/.toolchains/node-v24.15.0-linux-x64/bin/node" ]]; then
  export PATH="$moonport_root/.toolchains/node-v24.15.0-linux-x64/bin:$PATH"
fi
moonport_home="${MOONPORT_TOOLCHAIN_HOME:-.toolchains/linux-x86_64}"
if [[ "$moonport_home" != /* ]]; then moonport_home="$moonport_root/$moonport_home"; fi
export MOON_HOME="$moonport_home"
export PATH="$MOON_HOME/bin:$PATH"
moonport_action='verify'
if [[ "${BASH_SOURCE[0]}" == "$0" && "${1:-}" == 'install' ]]; then
  moonport_action='install'
fi
node "$moonport_root/scripts/toolchain.mjs" "$moonport_action"
