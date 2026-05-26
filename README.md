# Voice-to-Text with Whisper + AutoHotkey

Push-to-talk voice transcription on Windows. Trigger a hotkey, speak, and your words land in whatever app has focus.

- **F11** — clipboard-only mode. Copies the transcription to your clipboard (doesn't paste)
- **F12** — paste mode. Pastes the transcription at your cursor

Both hotkeys support two interaction styles:

- **Hold-to-talk:** press and hold the key while speaking, release when done (walkie-talkie style)
- **Tap-to-toggle:** tap once to start a hands-free recording, tap again to stop

For F12, the interaction style also controls the submit behavior:

- **Hold F12** → paste **and press Enter** (great for chat boxes, prompts, etc.)
- **Tap F12** → paste only (no Enter), so you can review before submitting

## How It Works

1. Trigger **F11** or **F12** (hold or tap) → Sox starts recording from your microphone
2. Stop recording (release the key, or tap the same key again) → Sox stops, ffmpeg fixes the WAV header, whisper.cpp transcribes the audio, and the text is delivered to your cursor or clipboard

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
   - **If you pick a different model**, override `WHISPER_MODEL` in `config.local.ahk` to match its filename (see [Configuration](#configuration) below) — otherwise transcription will fail and whisper's error message will appear wherever your cursor is.

## Configuration

### Local overrides (`config.local.ahk`)

The first time you launch `whisper-voice-to-text.ahk`, it auto-creates a `config.local.ahk` file next to it, pre-filled with every overridable setting at its default value. This file is **gitignored**, so any customizations you make stay local and won't conflict with future `git pull`s.

Workflow:

1. Double-click `whisper-voice-to-text.ahk` once — `config.local.ahk` appears in the same folder
2. Open `config.local.ahk` and edit any value
3. Reload the script (right-click the "H" tray icon → **Reload Script**, or just relaunch) so the new values take effect

The settings exposed in `config.local.ahk`:

- `WHISPER_EXE` — path to `whisper-cli.exe`
- `WHISPER_MODEL` — path to your model file (change this if you used a different model than the recommended one)
- `MIC_NAME` — your microphone name (see below for how to find it)

If you don't need to change anything, you can ignore the file entirely — the defaults stay in effect.

### Find your microphone name

Run this in a terminal to list available audio devices:

```
ffmpeg -list_devices true -f dshow -i dummy
```

Look for your microphone in the output. It will look something like:

```
"Microphone (Realtek(R) Audio)" (audio)
```

Copy the exact name and set it as the `MIC_NAME` value in `config.local.ahk`. If `"default"` works for you, no change is needed.

### Changing the hotkey or language

These two settings live in the main script rather than `config.local.ahk` (changing them is structural enough that you'll merge any future updates by hand):

- **Hotkey:** replace the hotkey definitions (`F11`, `F12`, and their `Up` counterparts) in `whisper-voice-to-text.ahk` with any keys you prefer. See the [AHK v2 key list](https://www.autohotkey.com/docs/v2/KeyList.htm) for options.
- **Language:** replace `-l en` in the whisper command with your language code (e.g., `-l es` for Spanish, `-l fr` for French). Remove `-l en` entirely to let whisper auto-detect the language.

## Run on Startup

The script won't start automatically after a reboot unless you configure it to. The easiest way:

1. Press **Win + R**, type `shell:startup`, and hit Enter — this opens your Startup folder
2. Right-click `whisper-voice-to-text.ahk` → **Create shortcut**
3. Move the shortcut into the Startup folder

The script will now launch automatically every time you log in.

## Usage

1. Double-click `whisper-voice-to-text.ahk` to start the script (you'll see an "H" icon in your system tray)
2. Click into any text field — a browser, editor, chat window, etc.
3. Start recording one of two ways:
   - **Hold-to-talk:** press and hold **F11** or **F12** while you speak, then release
   - **Tap-to-toggle:** tap **F11** or **F12** once to start a hands-free recording (the tooltip changes to "Recording (tap to stop)..."), then tap the same key again when you're done
4. A "Processing..." tooltip appears while whisper transcribes, then the text is delivered:
   - **F11** → copied to your clipboard
   - **F12 (held)** → pasted at your cursor, then **Enter** is pressed
   - **F12 (tapped)** → pasted at your cursor (no Enter — review before submitting)

If a recording is silent or shorter than 0.5 seconds, the script skips transcription entirely. This prevents whisper from hallucinating text like "Thank you" on empty audio, and also acts as a safety net for accidental key presses.

**First-run check:** for your first try, click into an empty text editor like Notepad. If something is misconfigured (wrong model path in `config.local.ahk`, missing binary, etc.), whisper's error message will be pasted instead of transcribed text — a quick way to find out what's wrong without needing a log.

## Troubleshooting

### Nothing happens when I press the hotkey
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
- This setup starts recording the moment you press the hotkey, so there shouldn't be clipping. If it happens, increase the `TAP_THRESHOLD_MS` value at the top of the script (it controls both the tap-vs-hold detection window and the sox startup delay before the "Recording..." tooltip appears).

## Notes

- The script kills sox by process name (`taskkill /im sox.exe`), so don't run other sox processes while using it
- Force-killing sox corrupts the WAV header, which is why ffmpeg is used as an intermediate fixup step
- Whisper model load time is ~1-2 seconds on first transcription; the actual transcription is fast on a GPU
- F12 pastes via clipboard (Ctrl+V) but restores your previous clipboard contents afterward. F11 (clipboard-only mode) leaves the transcribed text on your clipboard.
