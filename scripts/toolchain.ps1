param([switch]$Install)
$ErrorActionPreference = 'Stop'
$MoonPortRoot = Split-Path $PSScriptRoot -Parent
$MoonPortHome = if ($env:MOONPORT_TOOLCHAIN_HOME) { $env:MOONPORT_TOOLCHAIN_HOME } else { '.toolchains\windows-x86_64' }
if (-not [IO.Path]::IsPathRooted($MoonPortHome)) { $MoonPortHome = Join-Path $MoonPortRoot $MoonPortHome }
$env:MOON_HOME = [IO.Path]::GetFullPath($MoonPortHome)
$env:PATH = (Join-Path $env:MOON_HOME 'bin') + [IO.Path]::PathSeparator + $env:PATH
if ($Install) { & node (Join-Path $PSScriptRoot 'toolchain.mjs') install }
else { & node (Join-Path $PSScriptRoot 'toolchain.mjs') verify }
if ($LASTEXITCODE -ne 0) { throw 'MoonPortCheck toolchain validation failed.' }
