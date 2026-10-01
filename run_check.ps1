$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/scripts/toolchain.ps1"
Push-Location $PSScriptRoot
try {
  & node scripts/toolchain.mjs version
  if ($LASTEXITCODE -ne 0) { throw 'Toolchain check failed.' }
  & node scripts/api-check.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Public API check failed.' }
  & node --test 'scripts/*.test.mjs'
  if ($LASTEXITCODE -ne 0) { throw 'Engineering checks failed.' }
  & moon fmt --check
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit formatting check failed.' }
  & moon check --target js --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit JS typecheck failed.' }
  & moon check --target wasm-gc --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit wasm-gc typecheck failed.' }
  & moon test --target js --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit JS tests failed.' }
  & moon test --target wasm-gc --deny-warn
  if ($LASTEXITCODE -ne 0) { throw 'MoonBit wasm-gc tests failed.' }
  & "$PSScriptRoot/run_build.ps1"
  & node --test 'tests/*.test.mjs'
  if ($LASTEXITCODE -ne 0) { throw 'Node CLI tests failed.' }
  & node scripts/parity.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Cross-target parity check failed.' }
  & node scripts/format-matrix.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Report format consistency check failed.' }
  & node scripts/property.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Property and feature-cross check failed.' }
  & node scripts/bench.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Scale benchmark failed.' }
  & node scripts/code-stats.mjs --min 3000
  if ($LASTEXITCODE -ne 0) { throw 'Source statistics or LOC gate failed.' }
} finally { Pop-Location }
