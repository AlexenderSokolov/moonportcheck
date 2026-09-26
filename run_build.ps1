$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/scripts/toolchain.ps1"
Push-Location $PSScriptRoot
try {
  & moon build --target js --release --deny-warn src/bridge
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit JS build failed.' }
  $bridge = Join-Path $PSScriptRoot '_build/js/release/build/src/bridge/bridge.js'
  if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw "Build output missing: $bridge" }
  New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'dist') -Force | Out-Null
  Copy-Item -LiteralPath $bridge -Destination (Join-Path $PSScriptRoot 'dist/bridge.js')
} finally { Pop-Location }
