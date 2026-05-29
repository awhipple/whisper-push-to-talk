#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; DEFAULTS — to override, edit config.local.ahk (auto-created next to this script on first launch)
; ============================================================
global WHISPER_EXE := "C:\tools\whisper\whisper-server.exe"
global WHISPER_MODEL := "C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin"
global WHISPER_PORT := "8178"
global SOX_EXE := "sox"
global FFMPEG_EXE := "ffmpeg"
global RECORDING_FILE := A_Temp . "\whisper_recording.wav"
global FIXED_FILE := A_Temp . "\whisper_fixed.wav"
global MIC_NAME := "default"
global HOTKEY_CLIPBOARD := "F11"
global HOTKEY_PASTE := "F12"
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
        . "WHISPER_EXE := `"C:\tools\whisper\whisper-server.exe`"`r`n"
        . "WHISPER_MODEL := `"C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin`"`r`n"
        . "WHISPER_PORT := `"8178`"`r`n"
        . "SOX_EXE := `"sox`"`r`n"
        . "FFMPEG_EXE := `"ffmpeg`"`r`n"
        . "MIC_NAME := `"default`"`r`n"
        . "HOTKEY_CLIPBOARD := `"F11`"`r`n"
        . "HOTKEY_PASTE := `"F12`"`r`n"
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

global gServerPID := 0

; Tray menu shortcuts so users have a one-click path to their config
A_TrayMenu.Add()
A_TrayMenu.Add("Edit config", (*) => Run('notepad.exe "' . A_ScriptDir . '\config.local.ahk"'))
A_TrayMenu.Add("Open install folder", (*) => Run('explorer.exe "' . A_ScriptDir . '"'))

; Clean up the whisper server when the script exits or reloads
OnExit(StopWhisperServer)

; Launch whisper-server in the background so the model stays loaded in VRAM.
; The server accepts HTTP requests for transcription, eliminating the ~18s
; model-load penalty that whisper-cli pays on every invocation.
StartWhisperServer()

; --- Hotkey handlers (bound dynamically so the keys are configurable) --------

OnClipboardDown(*)
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

OnClipboardUp(*)
{
    global recording, toggleMode, recordStartTime, HOTKEY_CLIPBOARD
    if !recording
        return
    if (A_TickCount - recordStartTime < TAP_THRESHOLD_MS) {
        toggleMode := true
        ToolTip "Recording (tap " . HOTKEY_CLIPBOARD . " to stop)..."
        return
    }
    StopRecording()
}

OnPasteDown(*)
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

OnPasteUp(*)
{
    global recording, toggleMode, recordStartTime, autoSubmit, HOTKEY_PASTE
    if !recording
        return
    if (A_TickCount - recordStartTime < TAP_THRESHOLD_MS) {
        toggleMode := true
        autoSubmit := false
        ToolTip "Recording (tap " . HOTKEY_PASTE . " to stop)..."
        return
    }
    StopRecording()
}

Hotkey HOTKEY_CLIPBOARD, OnClipboardDown
Hotkey HOTKEY_CLIPBOARD . " Up", OnClipboardUp
Hotkey HOTKEY_PASTE, OnPasteDown
Hotkey HOTKEY_PASTE . " Up", OnPasteUp

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
    global recording, autoSubmit, RECORDING_FILE, FIXED_FILE, WHISPER_PORT, SOX_EXE, FFMPEG_EXE
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

    ; Transcribe via whisper-server HTTP API
    ToolTip "Processing..."
    if (!EnsureServerRunning()) {
        ToolTip
        return
    }
    outFile := A_Temp . "\whisper_response.txt"
    errFile := A_Temp . "\whisper_err.txt"
    try FileDelete(outFile)
    try FileDelete(errFile)
    curlCmd := 'curl.exe -s --max-time 30 -X POST "http://127.0.0.1:' . WHISPER_PORT . '/inference" -F "file=@' . FIXED_FILE . '" -F "response_format=text" >"' . outFile . '" 2>"' . errFile . '"'
    shell.Run(A_ComSpec . ' /c "' . curlCmd . '"', 0, true)
    ToolTip

    text := ""
    isError := false
    try {
        raw := FileRead(outFile)
        ; Whisper returns each segment on its own line; collapse into a single
        ; line so the pasted text reads naturally as a continuous paragraph.
        text := RegExReplace(raw, "\R+", " ")
        text := RegExReplace(text, " {2,}", " ")
        text := RegExReplace(text, "^\s+|\s+$", "")
    } catch {
        text := ""
    }

    ; If transcription is empty, surface the error so failures aren't silent
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

StartWhisperServer()
{
    global WHISPER_EXE, WHISPER_MODEL, WHISPER_PORT, gServerPID
    if (gServerPID && ProcessExist(gServerPID))
        ProcessClose(gServerPID)
    Run('"' . WHISPER_EXE . '" -m "' . WHISPER_MODEL . '" -l en --host 127.0.0.1 --port ' . WHISPER_PORT, , "Hide", &pid)
    gServerPID := pid
}

WaitForServer(timeout_ms := 30000)
{
    global WHISPER_PORT
    start := A_TickCount
    loop {
        try {
            whr := ComObject("WinHttp.WinHttpRequest.5.1")
            whr.Open("GET", "http://127.0.0.1:" . WHISPER_PORT . "/", false)
            whr.Send()
            if (whr.Status = 200)
                return true
        } catch {
        }
        if (A_TickCount - start > timeout_ms)
            return false
        Sleep 250
    }
}

EnsureServerRunning()
{
    global gServerPID
    if (!gServerPID || !ProcessExist(gServerPID))
        StartWhisperServer()
    return WaitForServer()
}

StopWhisperServer(*)
{
    global gServerPID
    if (gServerPID) {
        ProcessClose(gServerPID)
        gServerPID := 0
    }
}
