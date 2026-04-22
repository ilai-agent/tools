---
description: Download, analyze, transcribe and summarize a Loom or YouTube video. TRIGGER when user shares a Loom/YouTube URL and asks to analyze, summarize, or transcribe it.
argument-hint: <video-url> [--language he|en] [--no-transcribe] [--no-frames]
allowed-tools: Bash, Read, Glob
---

# Video Analyzer Skill

Analyze a video from Loom or YouTube: download, extract metadata, extract audio, transcribe (whisper.cpp), extract frames, and summarize.

## Pipeline

Run the analyzer script:

```bash
ANALYZER="/home/agent/agents/github-agent/projects/tracker/tools/video-analyzer/analyze.sh"
bash "$ANALYZER" "$ARGUMENTS"
```

Wait for the script to complete. It creates an output directory with:
- `video.mp4` — the downloaded video
- `metadata.json` — video metadata (title, duration, uploader)
- `audio.wav` — extracted audio track (16kHz mono)
- `transcript.txt` — whisper.cpp transcription
- `frames/` — one frame per second (JPG)

## After the pipeline finishes

1. **Read the transcript** from `transcript.txt` in the output directory. The output directory path is printed by the script.
2. **Read key frames** — look at frames at regular intervals (every 10-15 seconds) to understand visual content. Use the Read tool on JPG files.
3. **Read metadata** from `metadata.json` for title, duration, uploader.
4. **Generate a structured summary** in Hebrew with:
   - Title, duration, uploader
   - Full transcription (cleaned up, with timestamps if available)
   - Step-by-step visual description (correlating frames with transcript)
   - Key takeaways / action items

## Standalone transcription

To transcribe an audio file without the full pipeline:

```bash
TRANSCRIBE="/home/agent/agents/github-agent/projects/tracker/tools/video-analyzer/transcribe.sh"
bash "$TRANSCRIBE" <audio_file> --language he
```

## Dependencies

| Tool | Location | Purpose |
|------|----------|---------|
| analyze.sh | `tools/video-analyzer/analyze.sh` | Full pipeline orchestrator |
| transcribe.sh | `tools/video-analyzer/transcribe.sh` | Whisper.cpp wrapper |
| yt-dlp | `tools/video-analyzer/bin/yt-dlp` | Video downloader |
| whisper-cli | `~/whisper.cpp/build/bin/whisper-cli` | Transcription engine |
| ffmpeg | `~/.local/bin/ffmpeg` | Audio/video processing |

## Notes

- Default language: Hebrew (`he`). Use `--language en` for English.
- `--no-transcribe` skips transcription. `--no-frames` skips frame extraction.
- Output auto-created under `tools/video-analyzer/output/<video-id>/`.
- Re-runs skip already-downloaded files (idempotent).
