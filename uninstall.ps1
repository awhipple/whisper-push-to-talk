#Requires -Version 5.1

# whisper-push-to-talk uninstaller
#
# Usage (recommended): double-click uninstall.bat next to this file.
# Or from a terminal:  powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$InstallDir = "$env:LOCALAPPDATA\WhisperPushToTalk"
$TaskName   = "WhisperPushToTalk"

function Step($m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Info($m) { Write-Host "    $m" }
function OK($m)   { Write-Host "    [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    [warn] $m" -ForegroundColor Yellow }

Write-Host "This will:"
Write-Host "  - Stop the whisper push-to-talk script if it's running"
Write-Host "  - Remove the '$TaskName' scheduled task (frees F11/F12 at next logon too)"
Write-Host "  - Delete $InstallDir"
Write-Host "      (the .ahk script, config, sox, whisper.cpp, and the ~800 MB model)"
Write-Host ""
Write-Host "AutoHotkey and FFmpeg will be left installed in case other applications use them."
Write-Host "Instructions for removing those will be printed at the end if you want them gone too."
Write-Host ""
$confirm = Read-Host "Continue? (y/N)"
if ($confirm -notmatch '^[yY]') {
    Write-Host "Cancelled."
    exit 0
}

# ----- Stop the running AHK process (filtered to our script only) -----
Step "Stopping the running script"
$found = $false
try {
    $procs = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*whisper-voice-to-text*" }
    foreach ($p in $procs) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        OK "Stopped AutoHotkey process $($p.ProcessId)"
        $found = $true
    }
} catch {
    Warn "Couldn't enumerate processes: $($_.Exception.Message)"
}
if (-not $found) { Info "No running script process found" }

# ----- Remove the scheduled task -----
Step "Removing scheduled task '$TaskName'"
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    OK "Task removed"
} else {
    Info "Task not found (already removed?)"
}

# ----- Delete the install dir -----
Step "Deleting $InstallDir"
if (Test-Path $InstallDir) {
    try {
        Remove-Item -Recurse -Force $InstallDir
        OK "Folder deleted"
    } catch {
        Warn "Couldn't delete folder cleanly: $($_.Exception.Message)"
        Warn "Delete it manually if needed: $InstallDir"
    }
} else {
    Info "Folder didn't exist"
}

Write-Host ""
Write-Host "Uninstall complete." -ForegroundColor Green
Write-Host ""
Write-Host "AutoHotkey and FFmpeg are still installed. If no other apps need them, you can"
Write-Host "remove them with:"
Write-Host "  winget uninstall AutoHotkey.AutoHotkey"
Write-Host "  winget uninstall Gyan.FFmpeg"
Write-Host ""
