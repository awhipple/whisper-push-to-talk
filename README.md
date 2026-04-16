# Voice-to-Text with Whisper + AutoHotkey

Push-to-talk voice transcription on Windows. Hold a key, speak, release — your words get typed into whatever app has focus.

- **F11** — hold to record, pastes the transcribed text
- **F12** — same thing, but also presses Enter after pasting

## How It Works

1. Hold **F11** or **F12** → Sox starts recording from your microphone
2. Release the key → Sox stops, ffmpeg fixes the WAV header, whisper.cpp transcribes the audio, and the text is pasted at your cursor

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
   - You'll need to expand the **Assets** section at the bottom of the release to see all download options
   - **NVIDIA GPU (recommended):** Download `whisper-cublas-12.4.0-bin-x64.zip` for CUDA 12.x, or `whisper-cublas-11.8.0-bin-x64.zip` for CUDA 11.x — these use your GPU for much faster transcription
   - **CPU only (no NVIDIA GPU):** Download `whisper-bin-x64.zip` for a basic 64-bit build, or `whisper-blas-bin-x64.zip` for a CPU-optimized build using OpenBLAS
   - **32-bit Windows:** Use the `Win32` variants instead (`whisper-bin-Win32.zip` or `whisper-blas-bin-Win32.zip`)
2. Extract the zip and place the contents somewhere (e.g., `C:\tools\whisper\`)
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

Copy the exact name and set it as the `MIC_NAME` value at the top of the script. If `"default"` works for you, no change is needed.

### The Script

The script is included in this repo as `whisper-voice-to-text.ahk`. Open it and update the config variables at the top to match your setup before running.

### Changing the Hotkey

Replace the hotkey definitions (`F11`, `F12`, and their `Up` counterparts) with any keys you prefer. See the [AHK v2 key list](https://www.autohotkey.com/docs/v2/KeyList.htm) for options.

### Changing the Language

Replace `-l en` in the whisper command with your language code (e.g., `-l es` for Spanish, `-l fr` for French). Remove `-l en` entirely to let whisper auto-detect the language.

## Run on Startup

The script won't start automatically after a reboot unless you configure it to. The easiest way:

1. Press **Win + R**, type `shell:startup`, and hit Enter — this opens your Startup folder
2. Right-click `whisper-voice-to-text.ahk` → **Create shortcut**
3. Move the shortcut into the Startup folder

The script will now launch automatically every time you log in.

## Usage

1. Double-click `whisper-voice-to-text.ahk` to start the script (you'll see an "H" icon in your system tray)
2. Click into any text field — a browser, editor, chat window, etc.
3. Hold **F11** or **F12** and wait for the "Recording..." tooltip to appear
4. Speak your text
5. Release the key — a "Processing..." tooltip appears while whisper transcribes, then the text is pasted at your cursor (F12 also presses Enter)

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
