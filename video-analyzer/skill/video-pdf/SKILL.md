---
name: video-pdf
description: Full video analysis with PDF-ready HTML report — transcript, Claude summary, and chosen frames embedded. Use when the user wants a complete review document they can save or share.
argument-hint: <video-url> [--language he|en]
allowed-tools: Bash Read
---

# Video PDF Report

Full analysis pipeline + generates a self-contained HTML report (`report.html`) with:
- Video title, duration, uploader
- Claude-written summary and review
- All key frames embedded inline (base64)
- Full transcript

The HTML file can be opened in any browser and saved/printed as PDF.

## Pipeline

```bash
ANALYZER="${CLAUDE_SKILL_DIR}/../../analyze.sh"
bash "$ANALYZER" $ARGUMENTS --pdf
```

Wait for completion. The output directory and report path are printed at the end.

## Output files

| File | Content |
|------|---------|
| `video.mp4` | Downloaded video |
| `transcript.srt` | Timestamped transcription |
| `transcript.txt` | Plain-text transcription |
| `frames/frame_HH-MM-SS.jpg` | Key frames selected by Claude |
| `frames/manifest.txt` | Timestamp + reason per frame |
| `summary.md` | Claude summary |
| `report.html` | **Self-contained HTML report (print → PDF)** |

## After the pipeline finishes

1. Confirm `report.html` was created.
2. Tell the user the full path so they can open it in a browser.
3. Briefly summarize the video title and number of key frames included.

## Notes

- `report.html` is fully self-contained — images are base64-encoded inline.
- Open in any browser → File → Print → Save as PDF.
- Default language: Hebrew. Use `--language en` for English.
