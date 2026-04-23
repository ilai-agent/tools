---
name: video-short
description: Quick short summary of a Loom or YouTube video — transcript only, no frames. Faster than /analyze-video. Use when the user wants a brief overview without visual details.
argument-hint: <video-url> [--language he|en]
allowed-tools: Bash Read
---

# Video Short Summary

Fast mode: download → transcribe → Claude writes a concise 1-paragraph summary.
No frame extraction. Completes in roughly half the time of a full analysis.

## Pipeline

```bash
ANALYZER="${CLAUDE_SKILL_DIR}/../../analyze.sh"
bash "$ANALYZER" $ARGUMENTS --short
```

Wait for completion. The output directory is printed at the end.

## Output files

| File | Content |
|------|---------|
| `transcript.txt` | Full transcription |
| `summary.md` | Short summary (1-2 paragraphs) |

## After the pipeline finishes

1. Read `summary.md` — report it directly to the user.
2. If the user asks for more detail, run `/analyze-video` with the same URL.

## Notes

- Default language: Hebrew. Use `--language en` for English.
- Re-runs skip already-downloaded/transcribed files (idempotent).
- No frames are extracted in this mode.
