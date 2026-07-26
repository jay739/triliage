<#
.SYNOPSIS
  Compiles the Windows installer from an existing Flutter release build.

.DESCRIPTION
  Assumes `flutter build windows --release` has already run. Locates the Inno
  Setup compiler, installing it via Chocolatey if it is missing, then produces
  dist\triliage-<version>-windows-x64-setup.exe.

  Shared by CI and local builds on purpose, so the installer that ships is
  produced by exactly the same steps as the one built by hand.

.PARAMETER Version
  Version stamped into the installer and its filename. CI passes the release
  tag with the leading "v" stripped.

.EXAMPLE
  flutter build windows --release
  pwsh installer/build-installer.ps1 -Version 0.1.0
#>
[CmdletBinding()]
param(
    [string]$Version = '0.0.0-dev'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$script = Join-Path $PSScriptRoot 'triliage.iss'
$buildDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'

if (-not (Test-Path (Join-Path $buildDir 'triliage.exe'))) {
    throw "No Flutter release build at $buildDir. Run 'flutter build windows --release' first."
}

# Inno Setup lands in different places depending on how it was installed:
# Chocolatey and the machine-wide installer use Program Files, winget defaults
# to a per-user install under LOCALAPPDATA.
function Find-Iscc {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return $null
}

$iscc = Find-Iscc
if (-not $iscc) {
    Write-Host 'Inno Setup not found, installing via Chocolatey.'
    choco install innosetup -y --no-progress
    $iscc = Find-Iscc
}
if (-not $iscc) {
    throw 'Inno Setup compiler (ISCC.exe) not found and could not be installed.'
}

Write-Host "Using $iscc"
& $iscc "/DAppVersion=$Version" $script
if ($LASTEXITCODE -ne 0) {
    throw "ISCC.exe failed with exit code $LASTEXITCODE."
}

$output = Get-ChildItem -Path (Join-Path $repoRoot 'dist') -Filter '*.exe' |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
Write-Host "Installer: $($output.FullName) ($([math]::Round($output.Length / 1MB, 1)) MB)"
