# PhotoCraft GPU fix (Windows 10/11, 64-bit) - portable installer
#
# Installs Microsoft's DirectX Shader Compiler (DXC) next to photocraft.exe so the
# DirectX 12 backend can build PhotoCraft's compositing shader. Without it the
# legacy FXC compiler rejects the shader:
#
#   error X3507: 'blend_channel': Not all control paths return a value
#   GPU compositor: couldn't build the compositor's pipelines
#   ; using the CPU compositor
#
# ...and the app renders the canvas on the CPU on every launch.
#
# Usage:
#   INSTALL.cmd                       (double-click, finds PhotoCraft automatically)
#   INSTALL.cmd "D:\Apps\Photocraft"  (custom folder)
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Verify -Force

[CmdletBinding()]
param(
    [string]$InstallDir,
    [Alias('SkipPrefs')]
    [switch]$NoPrefs,
    [switch]$Verify,
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

# PhotoCraft keeps settings under %APPDATA%\Photocraft, or inside its own folder
# when it runs in portable mode.
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

function Get-UsesIntelGraphics {
    try {
        $ids = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | ForEach-Object { $_.PNPDeviceID })
        return (@($ids | Where-Object { $_ -match 'VEN_8086' }).Count -gt 0)
    } catch {
        return $false
    }
}

# Sets renderingMode=gpu, useGpu=true and, on Intel graphics, gpuBackend=dx12
# (PhotoCraft's DX12 backend then compiles shaders with the DXC we just installed).
function Update-Prefs([string]$path, [bool]$forceDx12) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        $backend = if ($forceDx12) { '    "gpuBackend": "dx12",' } else { '    "gpuBackend": "auto",' }
        $text = @(
            '{',
            '  "version": 2,',
            '  "performance": {',
            '    "renderingMode": "gpu",',
            '    "useGpu": true,',
            $backend.TrimEnd(','),
            '    "lowResolutionPreviews": true',
            '  }',
            '}'
        ) -join "`n"
        [IO.File]::WriteAllText($path, $text, $utf8NoBom)
        return $null
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path (Split-Path $path) ("preferences.backup-$stamp.json")
    Copy-Item -LiteralPath $path -Destination $backup -Force

    $text = [IO.File]::ReadAllText($path)

    if ($forceDx12) {
        if ($text -match '"gpuBackend"\s*:') {
            $text = $text -replace '("gpuBackend"\s*:\s*)"[^"]*"', '$1"dx12"'
        } elseif ($text -match '"performance"\s*:\s*\{') {
            $text = $text -replace '("performance"\s*:\s*\{)', ('$1' + "`n" + '    "gpuBackend": "dx12",')
        }
    }
    if ($text -match '"renderingMode"\s*:') {
        $text = $text -replace '("renderingMode"\s*:\s*)(null|"[^"]*")', '$1"gpu"'
    } elseif ($text -match '"performance"\s*:\s*\{') {
        $text = $text -replace '("performance"\s*:\s*\{)', ('$1' + "`n" + '    "renderingMode": "gpu",')
    }
    if ($text -match '"useGpu"\s*:') {
        $text = $text -replace '("useGpu"\s*:\s*)(true|false)', '$1true'
    } elseif ($text -match '"performance"\s*:\s*\{') {
        $text = $text -replace '("performance"\s*:\s*\{)', ('$1' + "`n" + '    "useGpu": true,')
    }

    $null = $text | ConvertFrom-Json
    [IO.File]::WriteAllText($path, $text, $utf8NoBom)
    return $backup
}

# ---------------------------------------------------------------- locate app

$InstallDir = Find-PhotoCraft $InstallDir
if (-not $InstallDir) {
    Write-Host ''
    Write-Host 'PhotoCraft was not found on this computer.' -ForegroundColor Yellow
    Write-Host 'Install PhotoCraft first (https://github.com/storytold/photocraft/releases),'
    Write-Host 'then run INSTALL.cmd again. If it is installed in a custom folder:'
    Write-Host '  INSTALL.cmd "D:\path\to\Photocraft"'
    exit 4
}

$exe = Join-Path $InstallDir 'photocraft.exe'
$dataDir = Get-DataDir $InstallDir
$intel = Get-UsesIntelGraphics

Write-Host ''
Write-Host ('PhotoCraft:        {0}' -f $InstallDir)
Write-Host ('Settings folder:   {0}' -f $dataDir)
Write-Host ('Intel graphics:    {0}' -f ($(if ($intel) { 'yes (DX12 backend will be set)' } else { 'no' })))
Write-Host ''

# ---------------------------------------------------------------- elevation

if (-not (Test-CanWrite $InstallDir)) {
    if (-not (Test-Admin)) {
        Write-Host 'Administrator rights are needed to write into the PhotoCraft folder.'
        Write-Host 'Accept the UAC prompt to continue...'
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
                     '-InstallDir', "`"$InstallDir`"")
        if ($NoPrefs) { $argList += '-NoPrefs' }
        if ($Verify) { $argList += '-Verify' }
        if ($Force) { $argList += '-Force' }
        try {
            $child = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList -Wait -PassThru
        } catch {
            Write-Warning 'Elevation was cancelled. Nothing was changed.'
            Write-Host ''
            Write-Host 'Without admin rights, start PhotoCraft through the included launcher:'
            Write-Host ('  ' + (Join-Path $PSScriptRoot 'PhotoCraft-GPU.cmd'))
            exit 2
        }
        exit $child.ExitCode
    }
    throw "Cannot write into $InstallDir."
}

# ---------------------------------------------------------------- running app

$running = @(Get-Process -Name photocraft -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    if (-not $Force) {
        $answer = Read-Host 'PhotoCraft is running. Close it and continue? [y/N]'
        if ($answer -notmatch '^(y|yes)$') {
            Write-Host 'Cancelled. Close PhotoCraft and run INSTALL.cmd again.'
            exit 5
        }
    }
    $running | Stop-Process -Force
    Start-Sleep -Milliseconds 1200
}

# ---------------------------------------------------------------- install files

$source = Join-Path $PSScriptRoot 'bin'
foreach ($dll in @('dxcompiler.dll', 'dxil.dll')) {
    $from = Join-Path $source $dll
    if (-not (Test-Path -LiteralPath $from)) { throw "Missing $from - extract the whole zip before running." }
    Copy-Item -LiteralPath $from -Destination (Join-Path $InstallDir $dll) -Force
    Write-Host ('Installed {0}' -f $dll)
}

# ---------------------------------------------------------------- preferences

$prefsPath = Join-Path $dataDir 'preferences.json'
if (-not $NoPrefs) {
    $backup = Update-Prefs $prefsPath $intel
    Write-Host ('Preferences: renderingMode=gpu, useGpu=true' + $(if ($intel) { ', gpuBackend=dx12' } else { '' }))
    if ($backup) { Write-Host ('  backup: {0}' -f $backup) }
} else {
    Write-Host 'Preferences left unchanged (-NoPrefs).'
}

# ---------------------------------------------------------------- verify

if ($Verify) {
    Write-Host ''
    Write-Host 'Starting PhotoCraft for a quick check (about 15 seconds)...'
    $logPath = Join-Path $dataDir 'logs\photocraft.log'
    $proc = Start-Process -FilePath $exe -PassThru
    Start-Sleep -Seconds 15
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
    Start-Sleep -Milliseconds 800

    $tail = ''
    if (Test-Path -LiteralPath $logPath) { $tail = Get-Content -LiteralPath $logPath -Raw }
    if ($tail -match 'using the CPU compositor' -or $tail -match "couldn't build the compositor") {
        Write-Warning 'Check failed: PhotoCraft still fell back to the CPU compositor.'
        Write-Host ('Log: {0}' -f $logPath)
        exit 3
    }
    if ($tail -match 'Plan \{ backend: (Dx12|Vulkan|Metal)') {
        Write-Host 'Check passed: the GPU backend started, no CPU-compositor fallback.'
    } else {
        Write-Host 'Files installed. The app started without a CPU-compositor fallback.'
        Write-Host ('Log: {0}' -f $logPath)
    }
}

Write-Host ''
Write-Host 'Done. Start PhotoCraft normally (Start Menu or shortcut).'
Write-Host 'Optional check: Preferences > Performance shows the GPU backend and adapter name.'
Write-Host 'To undo: run UNINSTALL.cmd.'
