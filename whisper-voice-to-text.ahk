#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; CONFIG — Update these paths to match your setup
; ============================================================
global WHISPER_EXE := "C:\tools\whisper\whisper-cli.exe"
global WHISPER_MODEL := "C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin"
global RECORDING_FILE := A_Temp . "\whisper_recording.wav"
global FIXED_FILE := A_Temp . "\whisper_fixed.wav"

; If your mic name is different, update this:
global MIC_NAME := "default"
; ============================================================

global recording := false
global autoSubmit := false

F11::
{
    global autoSubmit
    autoSubmit := false
    StartRecording()
}

F12::
{
    global autoSubmit
    autoSubmit := true
    StartRecording()
}

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

    ; Run whisper
    exec := shell.Exec(WHISPER_EXE . ' -m ' . WHISPER_MODEL . ' -l en -nt -f "' . FIXED_FILE . '"')
    raw := exec.StdOut.ReadAll()

    text := RegExReplace(raw, "^\s+|\s+$", "")
    if (text != "") {
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
