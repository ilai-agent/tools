---
name: analyze-video
description: Download, analyze, transcribe and summarize a Loom or YouTube video. TRIGGER when user shares a Loom/YouTube URL and asks to analyze, summarize, or transcribe it.
argument-hint: <video-url> [--language he|en] [--no-transcribe] [--no-frames]
allowed-tools: Bash Read Glob
---

# Video Analyzer — Full Analysis

Analyze a video from Loom or YouTube: download, extract metadata, extract audio,
transcribe (whisper.cpp), then use Claude to select key frames and write a summary.

## Pipeline

Run the analyzer script:

```bash
ANALYZER="${CLAUDE_SKILL_DIR}/../../analyze.sh"
bash "$ANALYZER" $ARGUMENTS
```

Wait for the script to complete. The output directory is printed at the end.

## Output files

| File | Content |
|------|---------|
| `video.mp4` | Downloaded video |
| `metadata.json` | Title, duration, uploader |
| `audio.wav` | Extracted audio (16kHz mono) |
| `transcript.srt` | Whisper transcription with timestamps |
| `transcript.txt` | Plain-text transcription |
| `frames/frame_HH-MM-SS.jpg` | Key frames selected by Claude |
| `frames/manifest.txt` | Timestamp + reason for each frame |
| `summary.md` | Claude-written summary |
| `claude_output.txt` | Raw Claude response (debug) |

## After the pipeline finishes

1. Read `summary.md` from the output directory.
2. Read `frames/manifest.txt` to see which frames were selected and why.
3. Optionally read a few key frame images to verify visual content.
4. Report back to the user: title, duration, summary, and list of key frames.

## Flags

| Flag | Effect |
|------|--------|
| `--language en` | Transcribe in English (default: Hebrew) |
| `--no-transcribe` | Skip transcription |
| `--no-frames` | Skip frame extraction |
| `--short` | Short summary only (no frames, faster) |
| `--pdf` | Generate HTML report with embedded frames |

## Standalone transcription

```bash
bash "${CLAUDE_SKILL_DIR}/../../transcribe.sh" <audio_file> --language he
```

## Dependencies

| Tool | Path | Purpose |
|------|------|---------|
| `yt-dlp` | `bin/yt-dlp` | Video downloader |
| `whisper-cli` | `~/whisper.cpp/build/bin/whisper-cli` | Transcription |
| `ffmpeg` | `~/.local/bin/ffmpeg` | Audio/video processing |
| `claude` | `PATH` | AI analysis |
