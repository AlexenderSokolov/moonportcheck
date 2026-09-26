$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    . (Join-Path $PSScriptRoot 'scripts/toolchain.ps1')
    & (Join-Path $PSScriptRoot 'run_build.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'MoonPortCheck build failed.' }
    & node (Join-Path $PSScriptRoot 'scripts/demo.mjs')
    if ($LASTEXITCODE -ne 0) { throw 'MoonPortCheck demonstration failed.' }
} finally {
    Pop-Location
}
