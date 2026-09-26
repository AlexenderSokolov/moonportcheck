param([switch]$Install)
$ErrorActionPreference = 'Stop'
$MoonPortRoot = Split-Path $PSScriptRoot -Parent
$env:MOON_HOME = Join-Path $MoonPortRoot '.toolchains\windows-x86_64'
$env:PATH = (Join-Path $env:MOON_HOME 'bin') + [IO.Path]::PathSeparator + $env:PATH
if ($Install) { & node (Join-Path $PSScriptRoot 'toolchain.mjs') install }
else { & node (Join-Path $PSScriptRoot 'toolchain.mjs') verify }
if ($LASTEXITCODE -ne 0) { throw 'MoonPortCheck toolchain validation failed.' }
