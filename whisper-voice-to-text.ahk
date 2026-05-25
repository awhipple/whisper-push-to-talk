#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; CONFIG — Update these paths to match your setup
; ============================================================
global WHISPER_EXE := "C:\tools\whisper\whisper-cli.exe"
global WHISPER_MODEL := "C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin"
global RECORDING_FILE := A_Temp . "\whisper_recording.wav"
global FIXED_FILE := A_Temp . "\whisper_fixed.wav"
global WHISPER_OUT := A_Temp . "\whisper_out"

; If your mic name is different, update this:
global MIC_NAME := "default"
; ============================================================

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
    try FileDelete(WHISPER_OUT . ".txt")
    shell.Run(WHISPER_EXE . ' -m ' . WHISPER_MODEL . ' -l en -nt -otxt -of "' . WHISPER_OUT . '" -f "' . FIXED_FILE . '"', 0, true)
    ToolTip

    try
        raw := FileRead(WHISPER_OUT . ".txt")
    catch
        return

    text := RegExReplace(raw, "^\s+|\s+$", "")
    if (text != "") {
        if clipboardOnly {
            A_Clipboard := text
            ToolTip "Copied to clipboard"
            SetTimer () => ToolTip(), -1500
        } else {
            prevClip := ClipboardAll()
            A_Clipboard := text
            Sleep 100
            Send("^v")
            if autoSubmit {
                Sleep 300
                SendEvent("{Enter}")
            }
            Sleep 100
            A_Clipboard := prevClip
        }
    }
}
