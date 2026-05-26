#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; DEFAULTS — to override, edit config.local.ahk (auto-created next to this script on first launch)
; ============================================================
global WHISPER_EXE := "C:\tools\whisper\whisper-cli.exe"
global WHISPER_MODEL := "C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin"
global SOX_EXE := "sox"
global FFMPEG_EXE := "ffmpeg"
global RECORDING_FILE := A_Temp . "\whisper_recording.wav"
global FIXED_FILE := A_Temp . "\whisper_fixed.wav"
global WHISPER_OUT := A_Temp . "\whisper_out"
global MIC_NAME := "default"
; ============================================================

; Pull in local overrides if present (gitignored, so `git pull` stays clean)
#Include *i %A_ScriptDir%\config.local.ahk

; Create the local config template on first launch so the user has something to edit
configFile := A_ScriptDir . "\config.local.ahk"
if !FileExist(configFile) {
    FileAppend(
        "; ============================================================`r`n"
        . "; Local config for whisper-voice-to-text -- NOT tracked in git`r`n"
        . "; ============================================================`r`n"
        . ";`r`n"
        . "; Edit any value below and save this file. To apply your changes:`r`n"
        . ";   1. Find the `"H`" icon in your system tray (bottom-right of the`r`n"
        . ";      taskbar; click the small up-arrow ^ to see hidden icons)`r`n"
        . ";   2. Right-click the `"H`" icon and choose `"Reload Script`"`r`n"
        . ";`r`n"
        . "; If you can't find the `"H`" icon, the script may not be running.`r`n"
        . "; Sign out and back in, or re-run the installer, to relaunch it.`r`n"
        . "`r`n"
        . "WHISPER_EXE := `"C:\tools\whisper\whisper-cli.exe`"`r`n"
        . "WHISPER_MODEL := `"C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin`"`r`n"
        . "SOX_EXE := `"sox`"`r`n"
        . "FFMPEG_EXE := `"ffmpeg`"`r`n"
        . "MIC_NAME := `"default`"`r`n"
    , configFile)
}

global recording := false
global autoSubmit := false
global clipboardOnly := false
global toggleMode := false
global recordStartTime := 0
; Tap-vs-hold threshold; also doubles as the sox startup delay before the "Recording..." tooltip appears.
; These two need to be the same value, otherwise a hold just over the tap window briefly flashes
; the hold tooltip before being overwritten by the toggle tooltip.
global TAP_THRESHOLD_MS := 200

; Tray menu shortcuts so users have a one-click path to their config
A_TrayMenu.Add()
A_TrayMenu.Add("Edit config", (*) => Run('notepad.exe "' . A_ScriptDir . '\config.local.ahk"'))
A_TrayMenu.Add("Open install folder", (*) => Run('explorer.exe "' . A_ScriptDir . '"'))

; Warm up whisper in the background a few seconds after startup. Without this,
; the very first transcription after boot pays the full cold-start cost (model
; load into VRAM, CUDA init, OS page-cache miss on the ~800 MB model file),
; which the user experiences as a 15-30s "stuck on Processing..." on their
; first F11/F12 press. Running it now means that cost is paid while they're
; still settling in at their desk, not when they're trying to use the feature.
SetTimer WarmupWhisper, -5000

F11::
{
    global recording, toggleMode, recordStartTime, clipboardOnly, autoSubmit
    if recording {
        if toggleMode {
            toggleMode := false
            StopRecording()
        }
        return
    }
    clipboardOnly := true
    autoSubmit := false
    recordStartTime := A_TickCount
    StartRecording()
}

F11 Up::
{
    global recording, toggleMode, recordStartTime
    if !recording
        return
    if (A_TickCount - recordStartTime < TAP_THRESHOLD_MS) {
        toggleMode := true
        ToolTip "Recording (tap F11 to stop)..."
        return
    }
    StopRecording()
}

F12::
{
    global recording, toggleMode, recordStartTime, clipboardOnly, autoSubmit
    if recording {
        if toggleMode {
            toggleMode := false
            autoSubmit := false
            StopRecording()
        }
        return
    }
    clipboardOnly := false
    autoSubmit := true
    recordStartTime := A_TickCount
    StartRecording()
}

F12 Up::
{
    global recording, toggleMode, recordStartTime, autoSubmit
    if !recording
        return
    if (A_TickCount - recordStartTime < TAP_THRESHOLD_MS) {
        toggleMode := true
        autoSubmit := false
        ToolTip "Recording (tap F12 to stop)..."
        return
    }
    StopRecording()
}

StartRecording()
{
    global recording, toggleMode, RECORDING_FILE, MIC_NAME, SOX_EXE, TAP_THRESHOLD_MS
    if recording
        return
    recording := true

    try FileDelete(RECORDING_FILE)

    Run('"' . SOX_EXE . '" -t waveaudio "' . MIC_NAME . '" -r 16000 -c 1 -b 16 "' . RECORDING_FILE . '"', , "Hide")
    Sleep TAP_THRESHOLD_MS
    ; Skip the "Recording..." tooltip if a tap-to-toggle already set its own message,
    ; or if recording was stopped during the Sleep above (e.g., two fast taps in a row)
    if (recording && !toggleMode)
        ToolTip "Recording..."
}

StopRecording()
{
    global recording, autoSubmit, RECORDING_FILE, FIXED_FILE, WHISPER_EXE, WHISPER_MODEL, SOX_EXE, FFMPEG_EXE
    if !recording
        return
    recording := false
    ToolTip

    ; Kill sox
    shell := ComObject("WScript.Shell")
    shell.Run("taskkill /im sox.exe /f", 0, true)
    Sleep 500

    ; Verify recording exists
    try {
        size := FileGetSize(RECORDING_FILE)
        if (size = 0)
            return
    } catch
        return

    ; Fix WAV header with ffmpeg (sox header is corrupted by force kill)
    try FileDelete(FIXED_FILE)
    shell.Run('"' . FFMPEG_EXE . '" -y -i "' . RECORDING_FILE . '" -c copy "' . FIXED_FILE . '"', 0, true)

    ; Skip silent or very short recordings to avoid whisper hallucinations
    statFile := A_Temp . "\whisper_stat.txt"
    try FileDelete(statFile)
    statCmd := '"' . SOX_EXE . '" "' . FIXED_FILE . '" -n stat 2>"' . statFile . '"'
    shell.Run(A_ComSpec . ' /c "' . statCmd . '"', 0, true)
    try
        statErr := FileRead(statFile)
    catch
        return
    if RegExMatch(statErr, "Length \(seconds\):\s+([\d.]+)", &durMatch)
        if (Float(durMatch[1]) < 0.5)
            return
    if RegExMatch(statErr, "Maximum\s+amplitude:\s+([\d.]+)", &maxMatch)
        if (Float(maxMatch[1]) < 0.005)
            return

    ; Run whisper (hidden window, output to file to avoid stealing focus)
    ToolTip "Processing..."
    errFile := A_Temp . "\whisper_err.txt"
    try FileDelete(WHISPER_OUT . ".txt")
    try FileDelete(errFile)
    whisperCmd := '"' . WHISPER_EXE . '" -m "' . WHISPER_MODEL . '" -l en -nt -otxt -of "' . WHISPER_OUT . '" -f "' . FIXED_FILE . '" 2>"' . errFile . '"'
    shell.Run(A_ComSpec . ' /c "' . whisperCmd . '"', 0, true)
    ToolTip

    text := ""
    isError := false
    try {
        raw := FileRead(WHISPER_OUT . ".txt")
        text := RegExReplace(raw, "^\s+|\s+$", "")
    } catch {
        text := ""
    }

    ; If whisper produced no transcription, surface its stderr so failures aren't silent
    if (text = "") {
        try {
            rawErr := FileRead(errFile)
            text := RegExReplace(rawErr, "^\s+|\s+$", "")
            if (text != "")
                isError := true
        } catch {
        }
    }

    if (text != "") {
        if clipboardOnly {
            A_Clipboard := text
            ToolTip(isError ? "Whisper error copied to clipboard" : "Copied to clipboard")
            SetTimer () => ToolTip(), -1500
        } else {
            prevClip := ClipboardAll()
            A_Clipboard := text
            Sleep 100
            Send("^v")
            if (autoSubmit && !isError) {
                Sleep 300
                SendEvent("{Enter}")
            }
            Sleep 100
            A_Clipboard := prevClip
        }
    }
}

WarmupWhisper()
{
    ; Best-effort: generate a 1-second silent WAV and run whisper-cli against it
    ; so the model gets loaded into VRAM and CUDA state is initialized. Any
    ; failure here is silent — the user-visible behavior is just "first
    ; transcription was slow", which is the status quo we're trying to improve.
    global FFMPEG_EXE, WHISPER_EXE, WHISPER_MODEL
    warmWav := A_Temp . "\whisper_warmup.wav"
    warmOut := A_Temp . "\whisper_warmup_out"
    try FileDelete(warmWav)
    try FileDelete(warmOut . ".txt")
    shell := ComObject("WScript.Shell")
    genCmd := '"' . FFMPEG_EXE . '" -y -f lavfi -i anullsrc=r=16000:cl=mono -t 1 -c:a pcm_s16le "' . warmWav . '"'
    shell.Run(A_ComSpec . ' /c "' . genCmd . '"', 0, true)
    if !FileExist(warmWav)
        return
    whisperCmd := '"' . WHISPER_EXE . '" -m "' . WHISPER_MODEL . '" -l en -nt -otxt -of "' . warmOut . '" -f "' . warmWav . '"'
    shell.Run(A_ComSpec . ' /c "' . whisperCmd . '"', 0, true)
    try FileDelete(warmWav)
    try FileDelete(warmOut . ".txt")
}
