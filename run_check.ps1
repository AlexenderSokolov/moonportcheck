$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/scripts/toolchain.ps1"
Push-Location $PSScriptRoot
try {
  & node scripts/toolchain.mjs version
  if ($LASTEXITCODE -ne 0) { throw 'Toolchain check failed.' }
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
} finally { Pop-Location }
