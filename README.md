# Voice-to-Text with Whisper + AutoHotkey

Push-to-talk voice transcription on Windows. Hold F11, speak, release — your words get typed into whatever app has focus.

## How It Works

1. **F11 held down** → Sox starts recording from your microphone
2. **F11 released** → Sox stops, ffmpeg fixes the WAV header, whisper.cpp transcribes the audio, and the text is pasted at your cursor

## Prerequisites

- Windows 10/11
- A working microphone
- [AutoHotkey v2](https://www.autohotkey.com/) (v2.0+, not v1)
- An NVIDIA GPU is recommended for fast transcription (CPU works but is slower)

## Installation

### 1. AutoHotkey v2

Download and install from https://www.autohotkey.com/. Make sure you install **v2**, not v1.

### 2. Sox (audio recording)

1. Download Sox for Windows from https://sourceforge.net/projects/sox/
2. Run the installer or extract to a folder (e.g., `C:\tools\sox`)
3. Add the Sox folder to your system PATH:
   - Search "Environment Variables" in the Start menu
   - Under System Variables, find `Path`, click Edit
   - Add the Sox directory (e.g., `C:\tools\sox`)
4. Verify: open a new terminal and run `sox --version`

### 3. FFmpeg (WAV header repair)

1. Download a Windows build from https://www.gyan.dev/ffmpeg/builds/ (get the "release essentials" zip)
2. Extract to a folder (e.g., `C:\tools\ffmpeg`)
3. Add the `bin` subfolder to your system PATH (e.g., `C:\tools\ffmpeg\bin`)
4. Verify: open a new terminal and run `ffmpeg -version`

### 4. Whisper.cpp (speech-to-text)

1. Download the latest release from https://github.com/ggerganov/whisper.cpp/releases
   - Grab the Windows binary (e.g., `whisper-cli.exe`)
2. Place it somewhere (e.g., `C:\tools\whisper\whisper-cli.exe`)
3. Download a model file — recommended: `ggml-large-v3-turbo-q8_0.bin`
   - Models are available from https://huggingface.co/ggerganov/whisper.cpp/tree/main
   - Smaller models (base, small, medium) are faster but less accurate
   - Place the model file alongside the exe (e.g., `C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin`)

## Configuration

### Find Your Microphone Name

Run this in a terminal to list available audio devices:

```
ffmpeg -list_devices true -f dshow -i dummy
```

Look for your microphone in the output. It will look something like:

```
"Microphone (Realtek(R) Audio)" (audio)
```

Copy the exact name — you'll need it for the script if it differs from the default.

### The Script

Save the following as `whisper-voice-to-text.ahk`:

```ahk
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

F11::
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

F11 Up::
{
    global recording, RECORDING_FILE, FIXED_FILE, WHISPER_EXE, WHISPER_MODEL
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
        A_Clipboard := text
        Sleep 100
        Send("^v")
    }
}
```

### Changing the Hotkey

Replace `F11` and `F11 Up` with any key you prefer. See the [AHK v2 key list](https://www.autohotkey.com/docs/v2/KeyList.htm) for options.

### Changing the Language

Replace `-l en` in the whisper command with your language code (e.g., `-l es` for Spanish, `-l fr` for French). Remove `-l en` entirely to let whisper auto-detect the language.

## Usage

1. Double-click `whisper-voice-to-text.ahk` to start the script (you'll see an "H" icon in your system tray)
2. Click into any text field — a browser, editor, chat window, etc.
3. Hold **F11** and wait for the "Recording..." tooltip to appear
4. Speak your text
5. Release **F11** — after a moment, the transcribed text will be pasted at your cursor

## Troubleshooting

### Nothing happens when I press F11
- Make sure AutoHotkey v2 is installed (not v1)
- Right-click the script and choose "Run as administrator" if needed

### Empty or 0-byte recording
- Run `ffmpeg -list_devices true -f dshow -i dummy` and verify your mic name
- Make sure no other application has exclusive access to your microphone
- Try `sox -t waveaudio default -r 16000 -c 1 -b 16 test.wav` manually to confirm sox can record

### Transcription is empty or wrong
- Test whisper manually: `whisper-cli.exe -m <model> -l en -nt -f <wav-file>`
- Try a different model size — larger models are more accurate but slower

### Sox process won't stop / WAV file keeps growing
- Run `taskkill /im sox.exe /f` to kill any lingering sox processes
- Delete the temp file: `del %TEMP%\whisper_recording.wav`

### Beginning of speech gets cut off
- This setup starts recording the moment you press F11, so there shouldn't be clipping. If it happens, increase the `Sleep 300` value in the F11 handler to give sox more startup time.

## Notes

- The script kills sox by process name (`taskkill /im sox.exe`), so don't run other sox processes while using it
- Force-killing sox corrupts the WAV header, which is why ffmpeg is used as an intermediate fixup step
- Whisper model load time is ~1-2 seconds on first transcription; the actual transcription is fast on a GPU
- The text is pasted via clipboard (Ctrl+V), so whatever was on your clipboard will be overwritten
