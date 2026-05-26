#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; DEFAULTS — to override, edit config.local.ahk (auto-created next to this script on first launch)
; ============================================================
global WHISPER_EXE := "C:\tools\whisper\whisper-cli.exe"
global WHISPER_MODEL := "C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin"
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
        "; Local overrides for whisper-voice-to-text (not tracked in git).`r`n"
        . "; Edit any value below and reload the script (right-click the tray icon -> Reload Script) for it to take effect.`r`n"
        . "`r`n"
        . "WHISPER_EXE := `"C:\tools\whisper\whisper-cli.exe`"`r`n"
        . "WHISPER_MODEL := `"C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin`"`r`n"
        . "MIC_NAME := `"default`"`r`n"
    , configFile)
}

global recording := false
global autoSubmit := false
global clipboardOnly := false

F10::
{
    global autoSubmit, clipboardOnly
    autoSubmit := false
    clipboardOnly := true
    StartRecording()
}

F11::
{
    global autoSubmit, clipboardOnly
    autoSubmit := false
    clipboardOnly := false
    StartRecording()
}

F12::
{
    global autoSubmit, clipboardOnly
    autoSubmit := true
    clipboardOnly := false
    StartRecording()
}

F10 Up::StopRecording()
F11 Up::StopRecording()
F12 Up::StopRecording()

StartRecording()
{
    global recording, RECORDING_FILE, MIC_NAME
    if recording
        return
    recording := true

    try FileDelete(RECORDING_FILE)

    Run('sox -t waveaudio ' . MIC_NAME . ' -r 16000 -c 1 -b 16 "' . RECORDING_FILE . '"', , "Hide")
    Sleep 300
    ToolTip "Recording..."
}

StopRecording()
{
    global recording, autoSubmit, RECORDING_FILE, FIXED_FILE, WHISPER_EXE, WHISPER_MODEL
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
    shell.Run('ffmpeg -y -i "' . RECORDING_FILE . '" -c copy "' . FIXED_FILE . '"', 0, true)

    ; Skip silent or very short recordings to avoid whisper hallucinations
    statFile := A_Temp . "\whisper_stat.txt"
    try FileDelete(statFile)
    shell.Run(A_ComSpec . ' /c sox "' . FIXED_FILE . '" -n stat 2>"' . statFile . '"', 0, true)
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
    shell.Run(A_ComSpec . ' /c ' . WHISPER_EXE . ' -m ' . WHISPER_MODEL . ' -l en -nt -otxt -of "' . WHISPER_OUT . '" -f "' . FIXED_FILE . '" 2>"' . errFile . '"', 0, true)
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
