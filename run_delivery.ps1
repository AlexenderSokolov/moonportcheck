$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/scripts/toolchain.ps1"
Push-Location $PSScriptRoot
try {
  & "$PSScriptRoot/run_build.ps1"
  & node --test tests/delivery.test.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Delivery CLI regression failed.' }
  & node scripts/delivery-parity.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Delivery public API parity failed.' }
  & node scripts/delivery-verification.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Delivery reference/scale verification failed.' }
  & node scripts/delivery-cases.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Delivery real/synthetic cases failed.' }
  & node scripts/delivery-fs.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Delivery filesystem conformance failed.' }
} finally { Pop-Location }
