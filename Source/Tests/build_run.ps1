# LZMA include test suite: struct layout guard, LZMA/LZMA2 roundtrips,
# executable filters, 7z reading/writing (with and without AES).
# Builds and runs every test for Win32 and Win64 (Delphi 13.2);
# with -D7 additionally cross-builds with Delphi 7 (oldest supported compiler).
# The AES tests build Wolfgang Ehrhardt's AES/SHA-256 units from source with
# range and overflow checks on ({$R+}{$Q+}) - the units set their own options
# in std.inc, the switches cover everything else (our Pascal code included).
# Exit code 0 = all green.
param(
  [string]$Dcc32 = 'C:\delphi\13.2\bin\dcc32.exe',
  [string]$Dcc64 = 'C:\delphi\13.2\bin\dcc64.exe',
  [string]$Lib32 = 'C:\delphi\13.2\lib\win32\release',
  [string]$Lib64 = 'C:\delphi\13.2\lib\win64\release',
  [string]$Eh    = 'C:\delphi\13.2\TLH\Packages\Ehrhardt',
  [switch]$D7,
  [string]$D7Root = 'C:\delphi\7',
  [string]$EhD7   = 'C:\delphi\7\TLH\Packages\Ehrhardt'
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$ns = 'System;Winapi;System.Win'
$fails = 0

# test name -> needs Ehrhardt (AES/SHA-256 from source, $R+ $Q+)
$tests = [ordered]@{ pSizes = $false; pRoundtrip = $false; pExe = $false; p7zRead = $false; p7zAes = $true; p7zWrite = $true }

foreach ($t in $tests.Keys) {
  if (-not (Test-Path "$t.dpr")) { continue }
  foreach ($p in '32','64') {
    $dcc = if ($p -eq '32') { $Dcc32 } else { $Dcc64 }
    $lib = if ($p -eq '32') { $Lib32 } else { $Lib64 }
    $u = $lib; $extra = @()
    if ($tests[$t]) { $u = "$Eh\AES;$Eh\CRC, Hash;$lib"; $extra = @('-$R+', '-$Q+') }
    New-Item -ItemType Directory -Force "out$p","dcu$p" | Out-Null
    Remove-Item "out$p\$t.exe" -ErrorAction SilentlyContinue # never run a stale binary after a failed build
    Write-Host "=== $t (Win$p) ===" -ForegroundColor Cyan
    & $dcc -B --no-config -NS"$ns" -U"$u" -E"out$p" -NU"dcu$p" @extra "$t.dpr" 2>&1 |
      Where-Object { $_ -match 'Error|Fatal|Warning' } | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    if (-not (Test-Path "out$p\$t.exe")) { Write-Host "BUILD FAILED $t Win$p" -ForegroundColor Red; $fails++; continue }
    & ".\out$p\$t.exe"
    if ($LASTEXITCODE -ne 0) { Write-Host "TEST FAILED $t Win$p (exit $LASTEXITCODE)" -ForegroundColor Red; $fails++ }
  }
}

if ($D7) {
  # D7's dcc32 blocks forever in headless environments if stdin stays open
  # -> ProcessStartInfo + StandardInput.Close()
  New-Item -ItemType Directory -Force "outD7","dcuD7" | Out-Null
  foreach ($t in $tests.Keys) {
    if (-not (Test-Path "$t.dpr")) { continue }
    Write-Host "=== $t (Delphi 7) ===" -ForegroundColor Cyan
    Remove-Item "outD7\$t.exe" -ErrorAction SilentlyContinue
    $u = "$D7Root\lib"; $extra = ' -$R+ -$Q+' # always: D7 with range checks catches C1118 (NativeUInt)
    if ($tests[$t]) { $u = "$EhD7\AES;$EhD7\CRC, Hash;$D7Root\lib" }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$D7Root\bin\dcc32.exe"
    $psi.Arguments = "-B -U`"$u`" -N0`"$PSScriptRoot\dcuD7`" -E`"$PSScriptRoot\outD7`"$extra `"$PSScriptRoot\$t.dpr`""
    $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $PSScriptRoot
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $so = $p.StandardOutput.ReadToEnd(); [void]$p.StandardError.ReadToEnd()
    $p.WaitForExit()
    ($so -split "`n") | Where-Object { $_ -match 'Error|Fatal|Fehler' } | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    if ($p.ExitCode -ne 0 -or -not (Test-Path "outD7\$t.exe")) { Write-Host "BUILD FAILED $t D7" -ForegroundColor Red; $fails++; continue }
    & ".\outD7\$t.exe"
    if ($LASTEXITCODE -ne 0) { Write-Host "TEST FAILED $t D7 (exit $LASTEXITCODE)" -ForegroundColor Red; $fails++ }
  }
}

if ($fails -eq 0) { Write-Host "`nALL TESTS OK" -ForegroundColor Green } else { Write-Host "`n$fails FAILURES" -ForegroundColor Red }
exit $fails
