$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/scripts/toolchain.ps1"
Push-Location $PSScriptRoot
try {
  & node scripts/acceptance.mjs
  if ($LASTEXITCODE -ne 0) { throw 'MoonPortCheck acceptance failed; inspect the retained artifacts.' }
} finally { Pop-Location }
