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
2. Stop recording (release the key, or tap the same key again) → Sox stops, ffmpeg fixes the WAV header, the audio is sent to a local whisper.cpp server for transcription, and the text is delivered to your cursor or clipboard

A persistent `whisper-server` process runs in the background with the model loaded in VRAM, so transcriptions complete in ~1-2 seconds instead of the ~18 seconds that reloading the model every time would take.

## Prerequisites

- Windows 10/11 (with [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/) — built into modern Windows; install "App Installer" from the Microsoft Store if missing)
- A working microphone
- An NVIDIA GPU is recommended for fast transcription (CPU works but is slower)

## Quick install (recommended)

1. [Download this repo as a zip](https://github.com/awhipple/whisper-push-to-talk/archive/refs/heads/master.zip) and extract it somewhere
2. Double-click **`install.bat`** in the extracted folder

The installer will:

- Install AutoHotkey v2 and FFmpeg via winget
- Download SOX, whisper.cpp (CUDA build if it detects an NVIDIA GPU, CPU build otherwise), and a ~800 MB transcription model
- Drop everything in `%LOCALAPPDATA%\WhisperPushToTalk\` and generate a `config.local.ahk` with absolute paths
- Register a scheduled task that auto-launches the script at every logon (faster than the Startup folder — see [Auto-launch at logon](#auto-launch-at-logon) below)
- Launch the script and open `config.local.ahk` in Notepad so you can tweak the mic name if needed

Look for the "H" icon in your system tray when it finishes. Hold or tap F11/F12 and you're up and running.

**Re-running `install.bat` is safe** — it works as an updater. Already-installed binaries are detected and skipped, the script is refreshed in place, and your `config.local.ahk` is preserved so any edits (like a custom `MIC_NAME`) stick around.

If anything fails, you can fall back to the manual steps below.

## Uninstalling

Run `uninstall.bat` from this repo. After a "press Y to confirm" prompt, it will:

- Stop the running script (filtered to only our process — won't affect any other AHK scripts you have running)
- Remove the `WhisperPushToTalk` scheduled task (frees F11/F12 permanently, not just until next logon)
- Delete `%LOCALAPPDATA%\WhisperPushToTalk\` (the .ahk script, config, sox, whisper.cpp, and the ~800 MB model)

**AutoHotkey and FFmpeg are deliberately left installed**, since they're common tools that other apps on your machine may rely on. If you're sure nothing else needs them, the uninstaller prints the exact `winget uninstall` commands to remove them yourself.

**Just want F11/F12 back temporarily?** Right-click the "H" tray icon → **Exit**. The script stops immediately. (At next logon the scheduled task brings it back — to stop *that* too, run the full uninstaller.)

**Lost the repo and need to clean up manually?**

- Stop the script: right-click the "H" tray icon → Exit, or end `AutoHotkey64.exe` in Task Manager
- Remove the scheduled task: open Task Scheduler (Win+R → `taskschd.msc`), find `WhisperPushToTalk`, delete it
- Delete the folder: `%LOCALAPPDATA%\WhisperPushToTalk\`

## Manual install

### 1. AutoHotkey v2

Download and install from https://www.autohotkey.com/. Make sure you install **v2**, not v1.

### 2. Sox (audio recording)

1. Download Sox for Windows from https://sourceforge.net/projects/sox/
2. Run the installer or extract to a folder (e.g., `C:\tools\sox`)
3. Either add the Sox folder to your system PATH, or set `SOX_EXE` in `config.local.ahk` to the full path of `sox.exe`
4. Verify: `sox --version` (if on PATH) or that the exe runs from its install location

### 3. FFmpeg (WAV header repair)

1. Download a Windows build from https://www.gyan.dev/ffmpeg/builds/ (get the "release essentials" zip)
2. Extract to a folder (e.g., `C:\tools\ffmpeg`)
3. Either add the `bin` subfolder to your system PATH, or set `FFMPEG_EXE` in `config.local.ahk` to the full path of `ffmpeg.exe`
4. Verify: `ffmpeg -version` (if on PATH)

### 4. Whisper.cpp (speech-to-text)

1. Download the latest release from https://github.com/ggerganov/whisper.cpp/releases
   - You'll need to expand the **Assets** section at the bottom of the release to see all download options
   - **NVIDIA GPU (recommended):** Download `whisper-cublas-12.4.0-bin-x64.zip` for CUDA 12.x, or `whisper-cublas-11.8.0-bin-x64.zip` for CUDA 11.x — these use your GPU for much faster transcription
   - **CPU only (no NVIDIA GPU):** Download `whisper-bin-x64.zip` for a basic 64-bit build, or `whisper-blas-bin-x64.zip` for a CPU-optimized build using OpenBLAS
   - **32-bit Windows:** Use the `Win32` variants instead (`whisper-bin-Win32.zip` or `whisper-blas-bin-Win32.zip`)
2. Extract the zip and place the contents somewhere (e.g., `C:\tools\whisper\`)
   - The script uses `whisper-server.exe` (not `whisper-cli.exe`) to keep the model loaded in VRAM between transcriptions
3. Download a model file — recommended: `ggml-large-v3-turbo-q8_0.bin`
   - Models are available from https://huggingface.co/ggerganov/whisper.cpp/tree/main
   - Smaller models (base, small, medium) are faster but less accurate
   - Place the model file alongside the exe (e.g., `C:\tools\whisper\models\ggml-large-v3-turbo-q8_0.bin`)
   - **If you pick a different model**, override `WHISPER_MODEL` in `config.local.ahk` to match its filename (see [Configuration](#configuration) below) — otherwise transcription will fail and whisper's error message will appear wherever your cursor is.

## Configuration

### Local overrides (`config.local.ahk`)

All user-tunable settings live in a `config.local.ahk` file next to the script. This file is **gitignored**, so customizations stay local and won't conflict with future `git pull`s.

- **Quick install:** the installer generates this file for you with absolute paths to every binary it placed.
- **Manual install:** the first time you launch the script, it auto-creates `config.local.ahk` pre-filled with default values you can edit.

To edit and apply changes:

1. Find the **"H" icon** in your system tray (bottom-right of the taskbar; click the small up-arrow `^` to see hidden icons)
2. Right-click the "H" icon → **Edit config** to open the file in Notepad
3. Save your changes, then right-click → **Reload Script** so the new values take effect

The tray menu also has an **Open install folder** shortcut if you ever need to poke around the install directory directly.

The settings:

- `WHISPER_EXE` — path to `whisper-server.exe`
- `WHISPER_MODEL` — path to your model file (change this if you used a different model than the default)
- `WHISPER_PORT` — port for the local whisper server (default: `"8178"`)
- `SOX_EXE` — path to `sox.exe` (or just `"sox"` if it's on your PATH)
- `FFMPEG_EXE` — path to `ffmpeg.exe` (or just `"ffmpeg"` if it's on your PATH)
- `MIC_NAME` — your microphone name (see below for how to find it)
- `HOTKEY_CLIPBOARD` — key for clipboard-only mode (default: `"F11"`)
- `HOTKEY_PASTE` — key for paste mode (default: `"F12"`)

Only function keys (F1–F24) are supported. See the [AHK v2 key list](https://www.autohotkey.com/docs/v2/KeyList.htm) for valid names.

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

### Changing the language

This setting lives in the main script rather than `config.local.ahk` (changing it is structural enough that you'll merge any future updates by hand):

- **Language:** replace `-l en` in the whisper command with your language code (e.g., `-l es` for Spanish, `-l fr` for French). Remove `-l en` entirely to let whisper auto-detect the language.

## Auto-launch at logon

**Quick install:** the installer registers a scheduled task called `WhisperPushToTalk` that fires on every logon. This runs noticeably faster than the Startup folder, which Windows throttles for several minutes after login to keep the UI responsive.

To disable or modify it: open **Task Scheduler** (Win+R → `taskschd.msc`), find `WhisperPushToTalk` in the task library, and disable or delete it.

**Manual install fallback** (if you skipped the installer): drop a shortcut to `whisper-voice-to-text.ahk` into your Startup folder.

1. Press **Win + R**, type `shell:startup`, hit Enter
2. Right-click `whisper-voice-to-text.ahk` → **Create shortcut**
3. Move the shortcut into the Startup folder

The script will launch at every login, just with the usual Windows Startup-folder delay.

## Usage

1. Make sure the script is running — look for the **"H" icon** in your system tray. The installer launches it automatically and re-launches it at every logon. If you did a manual install, double-click `whisper-voice-to-text.ahk` to start it.
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
- A `whisper-server` process runs in the background with the model loaded in VRAM (~900 MB GPU memory). It starts automatically with the script and is cleaned up on exit
- The first transcription after launch may take a few extra seconds while the server finishes loading the model; subsequent transcriptions are near-instant on a GPU
- F12 pastes via clipboard (Ctrl+V) but restores your previous clipboard contents afterward. F11 (clipboard-only mode) leaves the transcribed text on your clipboard.
