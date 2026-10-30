# Undo the PhotoCraft GPU fix: removes dxcompiler.dll / dxil.dll from the
# PhotoCraft folder and restores the newest preferences backup.
#
# Usage: UNINSTALL.cmd   (or with a custom folder: UNINSTALL.cmd "D:\Apps\Photocraft")

[CmdletBinding()]
param(
    [string]$InstallDir,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Test-CanWrite([string]$dir) {
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { return $false }
    try {
        $probe = Join-Path $dir ('.pc-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-PhotoCraft([string]$explicit) {
    if (-not [string]::IsNullOrWhiteSpace($explicit)) {
        $candidate = $explicit.TrimEnd('\')
        if ((Split-Path $candidate -Leaf) -ieq 'photocraft.exe') { $candidate = Split-Path $candidate -Parent }
        if (Test-Path -LiteralPath (Join-Path $candidate 'photocraft.exe')) { return $candidate }
        throw "photocraft.exe not found in $candidate"
    }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Photocraft'),
        (Join-Path $env:ProgramFiles 'PhotoCraft'),
        (Join-Path ${env:ProgramFiles(x86)} 'Photocraft'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Photocraft')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'photocraft.exe'))) { return $c }
    }
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $entries = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like '*PhotoCraft*' -and $_.InstallLocation }
    foreach ($e in $entries) {
        $loc = $e.InstallLocation.Trim('"').TrimEnd('\')
        if (Test-Path -LiteralPath (Join-Path $loc 'photocraft.exe')) { return $loc }
    }
    return $null
}

function Get-DataDir([string]$installDir) {
    if ($env:PHOTOCRAFT_CONFIG_DIR) { return $env:PHOTOCRAFT_CONFIG_DIR }
    $portableData = Join-Path $installDir 'PhotoCraftData'
    if ((Test-Path -LiteralPath (Join-Path $installDir 'portable.txt')) -or
        (Test-Path -LiteralPath (Join-Path $installDir 'PhotoCraft.portable')) -or
        (Test-Path -LiteralPath $portableData)) {
        return $portableData
    }
    return (Join-Path $env:APPDATA 'Photocraft')
}

$InstallDir = Find-PhotoCraft $InstallDir
if (-not $InstallDir) {
    Write-Host 'PhotoCraft was not found; nothing to undo.' -ForegroundColor Yellow
    exit 4
}
$dataDir = Get-DataDir $InstallDir

if (-not (Test-CanWrite $InstallDir)) {
    if (-not (Test-Admin)) {
        Write-Host 'Administrator rights are needed to change the PhotoCraft folder.'
        Write-Host 'Accept the UAC prompt to continue...'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
                     '-InstallDir', "`"$InstallDir`"")
        if ($Force) { $argList += '-Force' }
        try {
            $child = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait -PassThru
        } catch {
            Write-Warning 'Elevation was cancelled. Nothing was changed.'
            exit 2
        }
        exit $child.ExitCode
    }
    throw "Cannot write into $InstallDir."
}

$running = @(Get-Process -Name photocraft -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    if (-not $Force) {
        $answer = Read-Host 'PhotoCraft is running. Close it and continue? [y/N]'
        if ($answer -notmatch '^(y|yes)$') {
            Write-Host 'Cancelled.'
            exit 5
        }
    }
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 1200
}

foreach ($dll in @('dxcompiler.dll', 'dxil.dll')) {
    $path = Join-Path $InstallDir $dll
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        Write-Host ('Removed {0}' -f $path)
    }
}

$prefsPath = Join-Path $dataDir 'preferences.json'
$latest = Get-ChildItem -LiteralPath $dataDir -Filter 'preferences.backup-*.json' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($latest) {
    Copy-Item -LiteralPath $latest.FullName -Destination $prefsPath -Force
    Write-Host ('Restored preferences from {0}' -f $latest.Name)
} elseif (Test-Path -LiteralPath $prefsPath) {
    $text = [IO.File]::ReadAllText($prefsPath)
    $text = $text -replace '("gpuBackend"\s*:\s*)"[^"]*"', '$1"auto"'
    $text = $text -replace '("renderingMode"\s*:\s*)(null|"[^"]*")', '$1"auto"'
    $null = $text | ConvertFrom-Json
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($prefsPath, $text, $utf8NoBom)
    Write-Host 'Preferences reset to Automatic rendering.'
}

Write-Host ''
Write-Host 'Done. PhotoCraft is back to its previous graphics setup.'
