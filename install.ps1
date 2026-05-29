#Requires -Version 5.1

# whisper-push-to-talk installer
#
# Usage (recommended): double-click install.bat in this folder.
# Or from a terminal:  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # speeds up Invoke-WebRequest for small downloads

# Force UTF-8 console output so em-dashes etc. don't garble
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# ----- Paths -----
$InstallDir = "$env:LOCALAPPDATA\WhisperPushToTalk"
$BinDir     = "$InstallDir\bin"
$WhisperDir = "$InstallDir\whisper"
$ModelDir   = "$InstallDir\models"
$ConfigFile = "$InstallDir\config.local.ahk"
$AhkScript  = "$InstallDir\whisper-voice-to-text.ahk"
$RepoScript = "$PSScriptRoot\whisper-voice-to-text.ahk"

# ----- Console helpers -----
function Step($m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Info($m) { Write-Host "    $m" }
function OK($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [warn] $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "    [error] $m" -ForegroundColor Red; exit 1 }

# ============================================================
# Prerequisites
# ============================================================
Step "Checking prerequisites"

if (-not (Test-Path $RepoScript)) {
    Fail "Couldn't find whisper-voice-to-text.ahk next to install.ps1. Run this installer from the cloned/downloaded repo folder."
}
OK "Found whisper-voice-to-text.ahk"

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Fail "winget is required but not installed. Get 'App Installer' from the Microsoft Store, then re-run."
}
OK "winget available"

# ============================================================
# Winget install helper -surfaces winget output so failures are debuggable
# ============================================================
function Install-WingetPackage {
    param([string]$Id, [string]$DisplayName)
    Info "winget install $Id ..."
    & winget install --id $Id --silent --accept-source-agreements --accept-package-agreements
    $code = $LASTEXITCODE
    # 0 = installed, -1978335189 (0x8A150061) = already installed
    if ($code -eq 0 -or $code -eq -1978335189) {
        # winget often modifies user/machine PATH; refresh this session so subsequent
        # Get-Command lookups can find newly-installed binaries.
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        return
    }
    Fail "winget failed installing $DisplayName (exit code $code). See output above."
}

function Find-FirstExisting([string[]]$paths) {
    foreach ($p in $paths) { if ($p -and (Test-Path $p)) { return $p } }
    return $null
}

function Dump-DirContents([string]$dir, [string]$label) {
    if (Test-Path $dir) {
        Warn "$label contents of ${dir}:"
        Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "      $($_.FullName)" }
    } else {
        Warn "$label $dir does not exist."
    }
}

# ============================================================
# AutoHotkey v2 (via winget)
# ============================================================
function Find-AutoHotkey {
    # Prefer the top-level AutoHotkey.exe launcher over version-specific binaries.
    # The launcher reads the script's #Requires directive and dispatches to the right
    # runtime; it's what file association uses, and it works reliably across both
    # machine-scope and user-scope (winget-style) installs. Invoking AutoHotkey64.exe
    # directly has been observed to silently fail to launch a tray-resident script
    # in some user-scope install configurations.
    $candidates = [System.Collections.ArrayList]@(
        "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\AutoHotkey.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey32.exe",
        "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey32.exe"
    )
    # Add anything the Uninstall registry knows about (catches user-scope installs
    # under %LOCALAPPDATA%\Programs\AutoHotkey\, custom locations, etc.)
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($uk in $uninstallKeys) {
        Get-ItemProperty $uk -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -like '*AutoHotkey*' -and $_.InstallLocation
        } | ForEach-Object {
            $dir = $_.InstallLocation.TrimEnd('\')
            [void]$candidates.Add("$dir\AutoHotkey.exe")
            [void]$candidates.Add("$dir\v2\AutoHotkey64.exe")
            [void]$candidates.Add("$dir\v2\AutoHotkey32.exe")
            [void]$candidates.Add("$dir\AutoHotkey64.exe")
            [void]$candidates.Add("$dir\AutoHotkey32.exe")
        }
    }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

Step "Installing AutoHotkey v2"
Install-WingetPackage "AutoHotkey.AutoHotkey" "AutoHotkey v2"

$AhkExe = Find-AutoHotkey
if (-not $AhkExe) {
    Warn "winget reports AutoHotkey is installed but no executable was found on disk."
    Warn "Clearing winget's stale state and reinstalling..."
    & winget uninstall --id AutoHotkey.AutoHotkey --silent 2>&1 | Out-Null
    Install-WingetPackage "AutoHotkey.AutoHotkey" "AutoHotkey v2"
    $AhkExe = Find-AutoHotkey
}
if (-not $AhkExe) {
    Warn "AutoHotkey still not found after a clean reinstall attempt."
    Dump-DirContents "$env:ProgramFiles\AutoHotkey" "ProgramFiles"
    Dump-DirContents "${env:ProgramFiles(x86)}\AutoHotkey" "ProgramFiles(x86)"
    Fail "Could not locate AutoHotkey. Share the output above so the installer can be patched."
}
OK "AutoHotkey at $AhkExe"

# ============================================================
# FFmpeg (via winget)
# ============================================================
function Find-FFmpeg {
    # PATH (now refreshed by Install-WingetPackage)
    $found = (Get-Command ffmpeg.exe -ErrorAction SilentlyContinue).Source
    if ($found) { return $found }

    $static = @(
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe",
        "$env:ProgramFiles\ffmpeg\bin\ffmpeg.exe",
        "${env:ProgramFiles(x86)}\ffmpeg\bin\ffmpeg.exe"
    )
    foreach ($p in $static) {
        if (Test-Path $p) { return $p }
    }

    # winget portable installs (e.g., Gyan.FFmpeg) land deep under the Packages tree
    $pkgDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
    if (Test-Path $pkgDir) {
        $r = Get-ChildItem $pkgDir -Filter "ffmpeg.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($r) { return $r.FullName }
    }
    return $null
}

Step "Installing FFmpeg"
Install-WingetPackage "Gyan.FFmpeg" "FFmpeg"

$FfmpegExe = Find-FFmpeg
if (-not $FfmpegExe) {
    Warn "ffmpeg.exe not found anywhere expected."
    Dump-DirContents "$env:LOCALAPPDATA\Microsoft\WinGet\Links" "WinGet Links"
    Dump-DirContents "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" "WinGet Packages"
    Fail "Could not locate FFmpeg. Share the output above so the installer can be patched."
}
OK "FFmpeg at $FfmpegExe"

# ============================================================
# Install directories
# ============================================================
Step "Creating $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir, $BinDir, $WhisperDir, $ModelDir | Out-Null
OK "Directories ready"

# ============================================================
# SOX (portable zip from sourceforge)
# ============================================================
Step "Installing SOX 14.4.2"
$SoxExe = "$BinDir\sox\sox.exe"
if (Test-Path $SoxExe) {
    OK "Already installed at $SoxExe"
} else {
    $soxZip     = "$env:TEMP\sox.zip"
    $soxExtract = "$env:TEMP\sox-extract"
    if (Test-Path $soxExtract) { Remove-Item -Recurse -Force $soxExtract }
    $soxUrl = "https://sourceforge.net/projects/sox/files/sox/14.4.2/sox-14.4.2-win32.zip/download"
    Info "Downloading from sourceforge..."
    # curl.exe handles SourceForge's redirect chain better than Invoke-WebRequest
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L --fail --silent --show-error -o $soxZip $soxUrl
        if ($LASTEXITCODE -ne 0) { Fail "SOX download failed (curl exit $LASTEXITCODE)." }
    } else {
        Invoke-WebRequest -Uri $soxUrl -OutFile $soxZip -UseBasicParsing
    }
    # Sanity check -SourceForge sometimes serves an HTML interstitial instead of the file
    $magic = [System.IO.File]::ReadAllBytes($soxZip) | Select-Object -First 2
    if ($magic.Length -lt 2 -or $magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        $preview = (Get-Content $soxZip -TotalCount 5 -ErrorAction SilentlyContinue) -join "`n"
        Warn "Downloaded file is not a valid zip. First few lines:"
        Write-Host $preview
        Fail "SOX download returned something other than a zip (SourceForge may be serving HTML). Try re-running, or open an issue."
    }
    Info "Extracting..."
    Expand-Archive -Path $soxZip -DestinationPath $soxExtract -Force
    # Zip typically contains one top-level dir like "sox-14.4.2"
    $root = Get-ChildItem $soxExtract -Directory | Select-Object -First 1
    if ($root) {
        Move-Item $root.FullName "$BinDir\sox" -Force
    } else {
        Move-Item $soxExtract "$BinDir\sox" -Force
    }
    Remove-Item $soxZip -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $soxExtract -ErrorAction SilentlyContinue
    if (-not (Test-Path $SoxExe)) { Fail "sox.exe not found at $SoxExe after extraction" }
    OK "SOX at $SoxExe"
}

# ============================================================
# whisper.cpp (pick CUDA vs CPU build based on detected GPU)
# ============================================================
Step "Detecting GPU for whisper.cpp build selection"
$gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'NVIDIA' }
if ($gpu) {
    Info "NVIDIA GPU detected ($($gpu.Name)) - using cuBLAS build"
} else {
    Info "No NVIDIA GPU detected - using CPU build"
}

function Find-WhisperServer {
    if (-not (Test-Path $WhisperDir)) { return $null }
    $f = Get-ChildItem $WhisperDir -Filter "whisper-server.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.FullName }
    return $null
}

$WhisperServer = Find-WhisperServer
if ($WhisperServer) {
    Step "whisper.cpp already at $WhisperServer, skipping"
} else {
    Step "Looking up latest whisper.cpp release"
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggerganov/whisper.cpp/releases/latest" -UseBasicParsing
    } catch {
        Fail "Could not query whisper.cpp release info from GitHub: $($_.Exception.Message)"
    }
    Info "Latest release: $($release.tag_name)"

    # Pick the best asset based on GPU detection
    $zips = $release.assets | Where-Object { $_.name -like "*.zip" -and $_.name -match 'x64' }
    if ($gpu) {
        # Prefer cublas/cuda builds; the highest CUDA version is usually first when sorted desc
        $asset = $zips | Where-Object { $_.name -match 'cublas|cuda' } | Sort-Object name -Descending | Select-Object -First 1
    } else {
        # Prefer BLAS (CPU-optimized), fall back to plain build
        $asset = $zips | Where-Object { $_.name -match 'blas' -and $_.name -notmatch 'cu' } | Select-Object -First 1
        if (-not $asset) {
            $asset = $zips | Where-Object { $_.name -match '^whisper-bin-x64' } | Select-Object -First 1
        }
    }
    if (-not $asset) {
        Warn "No matching whisper.cpp zip in release $($release.tag_name). Available assets:"
        $zips | ForEach-Object { Write-Host "      $($_.name)" }
        Fail "No suitable whisper.cpp build found - the upstream naming convention may have changed."
    }
    Info "Selected: $($asset.name)"

    $whisperZip = "$env:TEMP\whisper.zip"
    Info "Downloading..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $whisperZip -UseBasicParsing
    Info "Extracting..."
    Expand-Archive -Path $whisperZip -DestinationPath $WhisperDir -Force
    Remove-Item $whisperZip -ErrorAction SilentlyContinue

    # The release zip's internal layout has changed across versions (sometimes at the root,
    # sometimes under a Release/ subfolder), so locate whisper-server.exe dynamically.
    $WhisperServer = Find-WhisperServer
    if (-not $WhisperServer) {
        Warn "whisper-server.exe not found anywhere under $WhisperDir after extraction. Contents:"
        Get-ChildItem $WhisperDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "      $($_.FullName)" }
        Fail "whisper-server.exe missing from the extracted archive."
    }
    OK "whisper.cpp $($release.tag_name) at $WhisperServer"
}

# ============================================================
# Model file (large-v3-turbo-q8_0, ~800 MB)
# ============================================================
$ModelName = "ggml-large-v3-turbo-q8_0.bin"
$ModelFile = "$ModelDir\$ModelName"
if (Test-Path $ModelFile) {
    Step "Model already at $ModelFile, skipping"
} else {
    Step "Downloading whisper model (~800 MB; takes a few minutes)"
    $modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$ModelName"
    # Use curl.exe (shipped with Windows 10+) for a real progress bar on the big download
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -L --fail -o $ModelFile $modelUrl
        if ($LASTEXITCODE -ne 0) { Fail "Model download failed (curl exit $LASTEXITCODE)" }
    } else {
        $ProgressPreference = "Continue"
        Invoke-WebRequest -Uri $modelUrl -OutFile $ModelFile -UseBasicParsing
        $ProgressPreference = "SilentlyContinue"
    }
    OK "Model at $ModelFile"
}

# ============================================================
# Copy the .ahk script into the install dir
# ============================================================
Step "Installing whisper-voice-to-text.ahk"
# Stop any currently running instance first so Copy-Item can overwrite the file
# (AHK keeps a handle on the script; re-running install.bat while it's running
# would silently fail to update the script).
try {
    $running = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*whisper-voice-to-text*" }
    foreach ($p in $running) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        Info "Stopped existing AutoHotkey process $($p.ProcessId) so the script can be overwritten"
    }
} catch {}
# Also stop any whisper-server left behind by the previous script session
try {
    Stop-Process -Name "whisper-server" -Force -ErrorAction SilentlyContinue
} catch {}
Copy-Item $RepoScript $AhkScript -Force
OK "Script at $AhkScript"

# ============================================================
# Generate config.local.ahk with absolute paths
# ============================================================
Step "Generating config.local.ahk"
if (Test-Path $ConfigFile) {
    OK "Config already exists at $ConfigFile - preserving your edits"
    $content = Get-Content $ConfigFile -Raw

    # Migrate WHISPER_EXE from whisper-cli to whisper-server if still pointing to old binary
    if ($content -match 'whisper-cli\.exe') {
        $content = $content -replace 'whisper-cli\.exe', 'whisper-server.exe'
        $content | Out-File -FilePath $ConfigFile -Encoding utf8 -Force
        OK "Updated WHISPER_EXE from whisper-cli.exe to whisper-server.exe"
    }

    # Add WHISPER_PORT if missing (new setting for server-based transcription)
    if ($content -notmatch 'WHISPER_PORT') {
        $addition = "`r`n; --- Added by installer update ---`r`nWHISPER_PORT := `"8178`""
        Add-Content -Path $ConfigFile -Value $addition
        OK "Added WHISPER_PORT setting to existing config"
    }

    Info "Delete the file and re-run the installer if you want fresh defaults."
} else {
    # AHK does not escape backslashes in string literals; write paths verbatim.
    $configContent = @"
; ============================================================
; Local config for whisper-voice-to-text -- NOT tracked in git
; ============================================================
;
; Edit any value below and save this file. To apply your changes:
;   1. Find the "H" icon in your system tray (bottom-right of the
;      taskbar; click the small up-arrow ^ to see hidden icons)
;   2. Right-click the "H" icon and choose "Reload Script"
;
; If you can't find the "H" icon, the script may not be running.
; Sign out and back in, or re-run the installer, to relaunch it.

WHISPER_EXE := "$WhisperServer"
WHISPER_MODEL := "$ModelFile"
WHISPER_PORT := "8178"
SOX_EXE := "$SoxExe"
FFMPEG_EXE := "$FfmpegExe"
MIC_NAME := "default"

; Hotkeys - use any single key name from the AHK v2 key list:
; https://www.autohotkey.com/docs/v2/KeyList.htm
; Only function keys (F1-F24) are supported.
HOTKEY_CLIPBOARD := "F11"   ; clipboard-only mode
HOTKEY_PASTE := "F12"       ; paste mode
"@
    $configContent | Out-File -FilePath $ConfigFile -Encoding utf8 -Force
    OK "Config at $ConfigFile"
}

# ============================================================
# Scheduled task -At Logon (faster than Startup folder)
# ============================================================
Step "Registering 'WhisperPushToTalk' scheduled task (At Logon)"
$taskName = "WhisperPushToTalk"
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
$action    = New-ScheduledTaskAction    -Execute $AhkExe -Argument "`"$AhkScript`""
$trigger   = New-ScheduledTaskTrigger   -AtLogOn -User $env:USERNAME
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
OK "Task registered -will launch on every logon"

# ============================================================
# Launch now
# ============================================================
Step "Launching whisper-voice-to-text"
Start-Process $AhkExe -ArgumentList "`"$AhkScript`""
OK "Launched - look for the 'H' icon in your system tray"

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""
Write-Host "Quick usage:"
Write-Host "  F11  hold or tap to record, copies to your clipboard (configurable)"
Write-Host "  F12  hold for paste + Enter, tap for paste-only (configurable)"
Write-Host ""
Write-Host "If you ever need to change the mic name or other settings, edit:"
Write-Host "  $ConfigFile"
Write-Host "Then right-click the 'H' tray icon -> Reload Script."
Write-Host ""
