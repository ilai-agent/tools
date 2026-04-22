# Video Analyzer

Download, transcribe, and analyze videos from Loom, YouTube, or any yt-dlp compatible URL.

## Structure

```
video-analyzer/
├── analyze.sh       # Main pipeline: download → metadata → audio → transcribe → frames
├── transcribe.sh    # Standalone whisper.cpp transcription wrapper
├── bin/
│   └── yt-dlp       # Video downloader (bundled)
└── README.md
```

## Dependencies

| Tool | Location | Purpose |
|------|----------|---------|
| yt-dlp | `bin/yt-dlp` (bundled) | Video download |
| ffmpeg | system PATH or `~/.local/bin/` | Audio/frame extraction |
| whisper.cpp | `~/whisper.cpp/` | Audio transcription |

## Usage

### Full analysis pipeline

```bash
./analyze.sh <URL> [--language he|en] [--frames N] [--no-transcribe]

# Examples:
./analyze.sh "https://www.loom.com/share/abc123def456..."
./analyze.sh "https://youtu.be/dQw4w9WgXcQ" --language en --frames 10
./analyze.sh "https://www.loom.com/share/..." --no-transcribe
```

Output goes to `/tmp/video-analysis/<video_id>/`:
- `video.mp4` — downloaded video
- `audio.wav` — 16kHz mono WAV (whisper format)
- `transcript.txt` — whisper transcription
- `metadata.json` — title, duration, uploader, resolution
- `frames/` — extracted key frames (PNG)

### Standalone transcription

```bash
./transcribe.sh <audio_file> [--language he|en] [--translate]

# Examples:
./transcribe.sh voice.ogg --language he
./transcribe.sh audio.wav --language en --translate
```

## Caching

Both scripts cache results — re-running with the same URL skips already-completed steps. Delete `/tmp/video-analysis/<video_id>/` to force a fresh run.
