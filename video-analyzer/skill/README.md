# Video Analyzer Skill for Claude Code

## What it does

A Claude Code slash command (`/analyze-video`) that takes a Loom or YouTube URL and:

1. **Downloads** the video (via yt-dlp)
2. **Extracts metadata** (title, duration, uploader)
3. **Extracts audio** (WAV 16kHz mono via ffmpeg)
4. **Transcribes** the audio (Hebrew/English via whisper.cpp)
5. **Extracts frames** (1 per second via ffmpeg)
6. **Summarizes** everything — visual + transcript — in Hebrew

## Installation

```bash
# User-level (available in all projects):
bash skill/install.sh

# Project-level (current repo only):
bash skill/install.sh --project
```

After installing, the `/analyze-video` command appears in Claude Code's `/help`.

## Usage

In Claude Code:

```
/analyze-video https://www.loom.com/share/19172e073ad64ed4a547c84e897a9001
/analyze-video https://youtu.be/dQw4w9WgXcQ --language en
/analyze-video https://www.loom.com/share/abc123 --no-transcribe
```

### Options

| Flag | Description |
|------|-------------|
| `--language he` | Transcribe in Hebrew (default) |
| `--language en` | Transcribe in English |
| `--no-transcribe` | Skip transcription |
| `--no-frames` | Skip frame extraction |

## Auto-trigger

The skill auto-triggers when you share a Loom or YouTube URL and ask to "analyze", "summarize", or "transcribe" it. No need to type `/analyze-video` explicitly.

## YouTube on VPS / Cloud Servers

> ⚠️ **If running on a VPS or cloud server**, YouTube blocks datacenter IP addresses and returns `LOGIN_REQUIRED` errors. This does **not** affect local machines (laptop/desktop).

**Fix: provide browser cookies.**

1. Install the [Get cookies.txt LOCALLY](https://chrome.google.com/webstore/detail/get-cookiestxt-locally/cclelndahbckbenkjhflpdbgdldlbecc) Chrome extension (or equivalent for Firefox).
2. Go to [youtube.com](https://youtube.com) while logged in to your Google account.
3. Click the extension → **Export** → save as `cookies.txt`.
4. Place the file at `~/.config/yt-dlp/cookies.txt` on the server.

yt-dlp will pick it up automatically. Cookies are typically valid for **1–3 months** before needing renewal.

## Dependencies

All must be pre-installed on the machine:

- **yt-dlp** — bundled in `bin/yt-dlp`
- **ffmpeg** — at `~/.local/bin/ffmpeg` or in PATH
- **whisper.cpp** — at `~/whisper.cpp/` (with `whisper-cli` built and `ggml-small.bin` model)

## Output

Each analysis creates a directory under `output/<video-id>/`:

```
output/<video-id>/
├── video.mp4          # Downloaded video
├── metadata.json      # Title, duration, uploader, etc.
├── audio.wav          # Extracted audio (16kHz mono)
├── transcript.txt     # Whisper transcription
└── frames/            # 1 frame per second
    ├── frame_0001.jpg
    ├── frame_0002.jpg
    └── ...
```

## File Structure

```
video-analyzer/
├── analyze.sh         # Main pipeline script
├── transcribe.sh      # Whisper.cpp wrapper
├── bin/
│   └── yt-dlp         # Video downloader binary
├── skill/
│   ├── analyze-video.md   # Claude Code skill definition
│   ├── install.sh         # Installation script
│   └── README.md          # This file
└── output/            # Analysis outputs (gitignored)
```
