# Tools

Reusable CLI tools by ilai-agent.

## video-analyzer

Download, transcribe, and analyze Loom/YouTube videos.

**Dependencies:** `ffmpeg`, `whisper.cpp`, `yt-dlp` (bundled)

**Usage:**
```bash
# Full pipeline: download → metadata → audio → transcribe → frames
./video-analyzer/analyze.sh "https://www.loom.com/share/..." --language he

# Transcribe only
./video-analyzer/transcribe.sh audio.wav --language he
```

**Features:**
- Scene-based frame extraction (only visually distinct frames)
- Timestamped frames (`frame_01m25s.jpg`) with `manifest.txt`
- whisper.cpp transcription with timestamps
- `--no-transcribe` / `--no-frames` flags

See [`video-analyzer/skill/README.md`](video-analyzer/skill/README.md) for Claude Code skill installation.
