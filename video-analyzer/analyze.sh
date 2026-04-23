#!/bin/bash
# Video Analyzer — Full pipeline: download → metadata → audio extract → transcribe (SRT) → Claude AI analysis
#
# AI Analysis (step 5): Claude CLI reads the transcript, selects key frames where visual
# references are made ("look at this", "תראה", "כאן", etc.), extracts those frames with
# ffmpeg, and writes a summary.md.  This replaces the old deterministic smart_frames.py.
#
# Usage:
#   ./analyze.sh <URL> [--output-dir DIR] [--language LANG] [--no-transcribe] [--no-frames]
#   ./analyze.sh <URL> --short   # transcript + brief summary only, no frames (fast)
#   ./analyze.sh <URL> --pdf     # full analysis + generate report.html (open in browser → Save as PDF)
#
# Examples:
#   ./analyze.sh "https://www.loom.com/share/abc123"
#   ./analyze.sh "https://youtu.be/xyz" --language en --output-dir /tmp/out
#   ./analyze.sh "https://www.loom.com/share/abc123" --short
#   ./analyze.sh "https://www.loom.com/share/abc123" --pdf

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YT_DLP="$SCRIPT_DIR/bin/yt-dlp"
# Prefer bundled ffmpeg (newer, tested with fHLS) → system PATH → ~/.local
FFMPEG="${FFMPEG_PATH:-$SCRIPT_DIR/bin/ffmpeg}"
if [ ! -x "$FFMPEG" ]; then
    FFMPEG="$(command -v ffmpeg 2>/dev/null || echo "$HOME/.local/bin/ffmpeg")"
fi
WHISPER_BIN="${WHISPER_BIN:-$HOME/whisper.cpp/build/bin/whisper-cli}"
WHISPER_MODELS="${WHISPER_MODELS:-$HOME/whisper.cpp/models}"
WHISPER_MODEL="${WHISPER_MODEL:-ggml-small.bin}"

# --- Defaults ---
LANGUAGE="he"
OUTPUT_DIR=""
DO_TRANSCRIBE=1
DO_FRAMES=1
DO_SHORT=0
DO_PDF=0
URL=""

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
        --language)    LANGUAGE="$2"; shift 2 ;;
        --no-transcribe) DO_TRANSCRIBE=0; shift ;;
        --no-frames)   DO_FRAMES=0; shift ;;
        --short)       DO_SHORT=1; DO_FRAMES=0; shift ;;
        --pdf)         DO_PDF=1; shift ;;
        -h|--help)
            echo "Usage: $0 <URL> [--output-dir DIR] [--language LANG] [--no-transcribe] [--no-frames] [--short] [--pdf]"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2; exit 1 ;;
        *)
            URL="$1"; shift ;;
    esac
done

if [ -z "$URL" ]; then
    echo "Error: URL is required." >&2
    echo "Usage: $0 <URL> [--output-dir DIR] [--language LANG] [--no-transcribe] [--no-frames] [--short] [--pdf]" >&2
    exit 1
fi

# --- Validate tools ---
if [ ! -x "$YT_DLP" ]; then
    echo "Error: yt-dlp not found at $YT_DLP" >&2
    exit 1
fi

if [ ! -x "$FFMPEG" ]; then
    echo "Error: ffmpeg not found. Set FFMPEG_PATH or install ffmpeg." >&2
    exit 1
fi

# --- Setup output directory ---
if [ -z "$OUTPUT_DIR" ]; then
    VIDEO_ID=$(echo "$URL" | grep -oP '[a-f0-9]{32}|[a-zA-Z0-9_-]{11}' | head -1 || echo "video")
    OUTPUT_DIR="/home/agent/agents/github-agent/video-analyze/output/$VIDEO_ID"
fi
mkdir -p "$OUTPUT_DIR/frames"

echo "=== Video Analyzer ==="
echo "URL: $URL"
echo "Output: $OUTPUT_DIR"
[ "$DO_SHORT" -eq 1 ] && echo "Mode: short (transcript + summary only)"
[ "$DO_PDF"   -eq 1 ] && echo "Mode: pdf (full analysis + HTML report)"
echo ""

# --- Step 1: Download video ---
echo "[1/5] Downloading video..."
VIDEO_FILE="$OUTPUT_DIR/video.mp4"
if [ -f "$VIDEO_FILE" ]; then
    echo "  -> Already downloaded, skipping."
else
    "$YT_DLP" -f "best[ext=mp4]/best" -o "$VIDEO_FILE" "$URL" 2>&1 | tail -3
    if [ ! -f "$VIDEO_FILE" ]; then
        echo "Error: Download failed." >&2
        exit 1
    fi
fi
echo "  -> Done: $(du -h "$VIDEO_FILE" | cut -f1)"
echo ""

# --- Step 2: Extract metadata ---
echo "[2/5] Extracting metadata..."
META_FILE="$OUTPUT_DIR/metadata.json"
"$YT_DLP" --dump-json --no-download "$URL" 2>/dev/null > "$META_FILE" || true
if [ -s "$META_FILE" ]; then
    TITLE=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('title','?'))" < "$META_FILE" 2>/dev/null || echo "?")
    DURATION=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('duration','?'))" < "$META_FILE" 2>/dev/null || echo "?")
    UPLOADER=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('uploader',d.get('channel','?')))" < "$META_FILE" 2>/dev/null || echo "?")
    echo "  -> Title: $TITLE"
    echo "  -> Duration: ${DURATION}s"
    echo "  -> Uploader: $UPLOADER"
else
    echo "  -> Metadata extraction failed (non-critical)."
    TITLE="?"
    DURATION=$("$FFMPEG" -i "$VIDEO_FILE" 2>&1 | grep Duration | awk '{print $2}' | tr -d , || echo "?")
    UPLOADER="?"
    echo "  -> Duration (ffmpeg): $DURATION"
fi
echo ""

# --- Step 3: Extract audio ---
echo "[3/5] Extracting audio..."
AUDIO_FILE="$OUTPUT_DIR/audio.wav"
if [ -f "$AUDIO_FILE" ]; then
    echo "  -> Already extracted, skipping."
else
    "$FFMPEG" -i "$VIDEO_FILE" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$AUDIO_FILE" -y 2>/dev/null
    if [ ! -f "$AUDIO_FILE" ]; then
        echo "  -> No audio stream found (silent video)."
        DO_TRANSCRIBE=0
    fi
fi
if [ -f "$AUDIO_FILE" ]; then
    echo "  -> Done: $(du -h "$AUDIO_FILE" | cut -f1)"
fi
echo ""

# --- Step 4: Transcribe with timestamps (SRT + plain text) ---
echo "[4/5] Transcribing..."
TRANSCRIPT_FILE="$OUTPUT_DIR/transcript.txt"
TRANSCRIPT_SRT="$OUTPUT_DIR/transcript.srt"

if [ "$DO_TRANSCRIBE" -eq 0 ]; then
    echo "  -> Skipped."
elif [ -f "$TRANSCRIPT_SRT" ]; then
    echo "  -> Already transcribed (SRT), skipping."
else
    if [ ! -f "$WHISPER_BIN" ]; then
        echo "  -> whisper-cli not found at $WHISPER_BIN, skipping." >&2
        DO_TRANSCRIBE=0
    elif [ ! -f "$WHISPER_MODELS/$WHISPER_MODEL" ]; then
        echo "  -> Whisper model not found at $WHISPER_MODELS/$WHISPER_MODEL, skipping." >&2
        DO_TRANSCRIBE=0
    else
        # Whisper saves output files next to the audio file using -of <base> flag.
        TRANSCRIPT_BASE="$OUTPUT_DIR/transcript"
        "$WHISPER_BIN" \
            -m "$WHISPER_MODELS/$WHISPER_MODEL" \
            -l "$LANGUAGE" \
            -f "$AUDIO_FILE" \
            -osrt \
            -otxt \
            -of "$TRANSCRIPT_BASE" \
            2>/dev/null || true

        if [ -f "${TRANSCRIPT_BASE}.srt" ]; then
            mv "${TRANSCRIPT_BASE}.srt" "$TRANSCRIPT_SRT"
        fi
        if [ -f "${TRANSCRIPT_BASE}.txt" ]; then
            mv "${TRANSCRIPT_BASE}.txt" "$TRANSCRIPT_FILE"
        fi

        # Fallback: if whisper wrote to stdout only (older builds), capture that
        if [ ! -f "$TRANSCRIPT_SRT" ] && [ ! -f "$TRANSCRIPT_FILE" ]; then
            "$WHISPER_BIN" \
                -m "$WHISPER_MODELS/$WHISPER_MODEL" \
                -l "$LANGUAGE" \
                -f "$AUDIO_FILE" \
                2>/dev/null > "$TRANSCRIPT_FILE" || true
        fi

        if [ -f "$TRANSCRIPT_SRT" ]; then
            ENTRY_COUNT=$(grep -c '^[0-9]\+$' "$TRANSCRIPT_SRT" 2>/dev/null || echo "0")
            echo "  -> Done: $ENTRY_COUNT subtitle entries with timestamps (SRT)"
        elif [ -f "$TRANSCRIPT_FILE" ]; then
            WORD_COUNT=$(wc -w < "$TRANSCRIPT_FILE")
            echo "  -> Done: $WORD_COUNT words (plain text, no timestamps)"
        else
            echo "  -> Transcription failed." >&2
            DO_TRANSCRIBE=0
        fi
    fi
fi
echo ""

# --- Step 5: Claude AI Analysis (frame selection + summary) ---
if [ "$DO_SHORT" -eq 1 ]; then
    echo "[5/5] Running Claude AI analysis (short summary mode)..."
else
    echo "[5/5] Running Claude AI analysis (frame selection + summary)..."
fi

# Determine available transcript
TRANSCRIPT_SOURCE=""
if [ -f "$TRANSCRIPT_SRT" ]; then
    TRANSCRIPT_SOURCE="$TRANSCRIPT_SRT"
elif [ -f "$TRANSCRIPT_FILE" ]; then
    TRANSCRIPT_SOURCE="$TRANSCRIPT_FILE"
fi

if [ -z "$TRANSCRIPT_SOURCE" ]; then
    echo "  -> No transcript available — skipping AI analysis."
    echo "     (Re-run without --no-transcribe to enable AI analysis.)"
elif ! command -v claude &>/dev/null; then
    echo "  -> claude CLI not found — skipping AI analysis." >&2
else
    PROMPT_FILE=$(mktemp /tmp/va_prompt_XXXXXX.txt)
    CLAUDE_OUTPUT_FILE="$OUTPUT_DIR/claude_output.txt"

    if [ "$DO_SHORT" -eq 1 ]; then
        # ── SHORT MODE: concise summary prompt, no frame selection ──
        cat > "$PROMPT_FILE" << 'PROMPT_END'
You are analyzing a video transcript. Write a concise 1-2 paragraph summary of the video.
Cover: the main topic, the key points made, and any conclusions or action items.
Be direct and informative. Do NOT include timestamps or frame references.

Output EXACTLY this format:
SUMMARY:
Your summary here.

Here is the transcript:
---
PROMPT_END

        cat "$TRANSCRIPT_SOURCE" >> "$PROMPT_FILE"
        echo "  -> Sending transcript to Claude (short mode)..."

        if claude -p "$(cat "$PROMPT_FILE")" \
            --dangerously-skip-permissions \
            --output-format text \
            > "$CLAUDE_OUTPUT_FILE" 2>/dev/null; then

            python3 - "$CLAUDE_OUTPUT_FILE" "$OUTPUT_DIR/summary.md" << 'PYEOF'
import sys, re

output_file = sys.argv[1]
summary_path = sys.argv[2]

with open(output_file) as f:
    content = f.read()

summary_match = re.search(r'SUMMARY:\s*(.*)', content, re.DOTALL)
summary = summary_match.group(1).strip() if summary_match else content.strip()

with open(summary_path, "w") as f:
    f.write(summary)
print(f"  -> Summary saved ({len(summary.split())} words)")
PYEOF
        else
            echo "  -> Claude CLI returned an error." >&2
        fi

    else
        # ── FULL MODE: frame selection + detailed summary ──
        cat > "$PROMPT_FILE" << 'PROMPT_END'
You are analyzing a video transcript. Perform two tasks:

TASK 1 — Frame selection:
Read the transcript carefully and identify timestamps where the speaker makes a visual
reference — moments where seeing the screen is important to understand what they mean.
Look for: pointing words ("here", "this", "כאן", "זה"), demonstration phrases
("as I'm doing now", "כמו שאני עושה", "watch", "תראה"), screen references
("see this button", "notice the", "שים לב ל"), etc.
Only select timestamps that genuinely benefit from a screenshot. Skip pure narration.

TASK 2 — Summary:
Write a concise, informative summary of the video content (2-4 paragraphs).
Cover the main topic, key points, and any conclusions or action items.

Output EXACTLY this format — nothing before FRAMES_JSON, nothing after the summary,
no markdown code fences:

FRAMES_JSON:
[
  {"timestamp": "HH:MM:SS", "reason": "short reason why this frame helps"},
  {"timestamp": "HH:MM:SS", "reason": "short reason why this frame helps"}
]
SUMMARY:
Your summary here. Multiple paragraphs are fine.

If there are no visual references, use an empty array:
FRAMES_JSON:
[]
SUMMARY:
Your summary here.

Here is the transcript:
---
PROMPT_END

        cat "$TRANSCRIPT_SOURCE" >> "$PROMPT_FILE"
        echo "  -> Sending transcript to Claude (may take ~30s)..."

        if claude -p "$(cat "$PROMPT_FILE")" \
            --dangerously-skip-permissions \
            --output-format text \
            > "$CLAUDE_OUTPUT_FILE" 2>/dev/null; then

            echo "  -> Claude analysis complete."

            # Parse Claude output with Python
            TIMESTAMPS_FILE="$OUTPUT_DIR/.frame_timestamps.txt"
            python3 - "$CLAUDE_OUTPUT_FILE" "$OUTPUT_DIR/summary.md" "$TIMESTAMPS_FILE" << 'PYEOF'
import sys, re, json

output_file = sys.argv[1]
summary_path = sys.argv[2]
timestamps_path = sys.argv[3]

with open(output_file) as f:
    content = f.read()

# Extract FRAMES_JSON block
frames = []
frames_match = re.search(r'FRAMES_JSON:\s*(\[.*?\])', content, re.DOTALL)
if frames_match:
    try:
        frames = json.loads(frames_match.group(1))
    except json.JSONDecodeError as e:
        print(f"  -> Warning: could not parse FRAMES_JSON: {e}", file=sys.stderr)

# Extract SUMMARY block
summary = ""
summary_match = re.search(r'SUMMARY:\s*(.*)', content, re.DOTALL)
if summary_match:
    summary = summary_match.group(1).strip()

# Save summary
if summary:
    with open(summary_path, "w") as f:
        f.write(summary)
    word_count = len(summary.split())
    print(f"  -> Summary saved ({word_count} words)")
else:
    print("  -> Warning: no SUMMARY found in Claude output", file=sys.stderr)

# Save timestamps
if frames:
    with open(timestamps_path, "w") as f:
        for item in frames:
            ts = item.get("timestamp", "").strip()
            reason = item.get("reason", "").strip().replace("|", " ")
            if ts:
                f.write(f"{ts}|{reason}\n")
    print(f"  -> {len(frames)} visual reference timestamps selected")
else:
    print("  -> No visual references found — no frames to extract")
PYEOF

            # Extract frames using Claude's selected timestamps
            if [ "$DO_FRAMES" -eq 1 ] && [ -f "$TIMESTAMPS_FILE" ] && [ -s "$TIMESTAMPS_FILE" ] && [ -f "$VIDEO_FILE" ]; then
                FRAME_COUNT=0
                > "$OUTPUT_DIR/frames/manifest.txt"  # clear manifest
                while IFS='|' read -r TS REASON; do
                    [ -z "$TS" ] && continue
                    TS_SAFE="${TS//:/-}"
                    FRAME_FILE="$OUTPUT_DIR/frames/frame_${TS_SAFE}.jpg"
                    if "$FFMPEG" -ss "$TS" -i "$VIDEO_FILE" -frames:v 1 -q:v 2 "$FRAME_FILE" -y 2>/dev/null; then
                        echo "${TS} — ${REASON}" >> "$OUTPUT_DIR/frames/manifest.txt"
                        FRAME_COUNT=$((FRAME_COUNT + 1))
                    else
                        echo "  -> Warning: failed to extract frame at $TS" >&2
                    fi
                done < "$TIMESTAMPS_FILE"
                rm -f "$TIMESTAMPS_FILE"
                echo "  -> Extracted $FRAME_COUNT frames"
            elif [ "$DO_FRAMES" -eq 0 ]; then
                echo "  -> Frame extraction skipped (--no-frames)."
            fi

        else
            echo "  -> Claude CLI returned an error — AI analysis skipped." >&2
        fi
    fi

    rm -f "$PROMPT_FILE"
fi
echo ""

# --- Step 6: Generate HTML report (--pdf mode) ---
if [ "$DO_PDF" -eq 1 ]; then
    echo "[6/6] Generating HTML report..."
    REPORT_FILE="$OUTPUT_DIR/report.html"

    python3 - "$OUTPUT_DIR" "$REPORT_FILE" "$TITLE" "$DURATION" "$UPLOADER" "$URL" << 'PYEOF'
import sys, os, re, base64, html
from datetime import datetime

out_dir    = sys.argv[1]
report_path = sys.argv[2]
title      = sys.argv[4] if len(sys.argv) > 4 else "?"
duration   = sys.argv[5] if len(sys.argv) > 5 else "?"
uploader   = sys.argv[6] if len(sys.argv) > 6 else "?"
url        = sys.argv[7] if len(sys.argv) > 7 else ""

# Read summary
summary_file = os.path.join(out_dir, "summary.md")
summary_html = ""
if os.path.exists(summary_file):
    with open(summary_file) as f:
        text = f.read()
    # Simple markdown → HTML: paragraphs separated by blank lines
    paragraphs = re.split(r'\n\s*\n', text.strip())
    summary_html = "\n".join(f"<p>{html.escape(p.strip())}</p>" for p in paragraphs if p.strip())
else:
    summary_html = "<p><em>No summary available.</em></p>"

# Read transcript
transcript_html = ""
for fname in ("transcript.srt", "transcript.txt"):
    tfile = os.path.join(out_dir, fname)
    if os.path.exists(tfile):
        with open(tfile) as f:
            transcript_html = f"<pre>{html.escape(f.read())}</pre>"
        break
if not transcript_html:
    transcript_html = "<p><em>No transcript available.</em></p>"

# Read frames
frames_html = ""
manifest_file = os.path.join(out_dir, "frames", "manifest.txt")
frames_dir = os.path.join(out_dir, "frames")
if os.path.exists(manifest_file):
    with open(manifest_file) as f:
        lines = [l.strip() for l in f if l.strip()]
    for line in lines:
        # Format: "HH:MM:SS — reason"
        parts = line.split(" — ", 1)
        ts = parts[0].strip() if parts else ""
        reason = parts[1].strip() if len(parts) > 1 else ""
        ts_safe = ts.replace(":", "-")
        img_file = os.path.join(frames_dir, f"frame_{ts_safe}.jpg")
        img_tag = ""
        if os.path.exists(img_file):
            with open(img_file, "rb") as f:
                b64 = base64.b64encode(f.read()).decode()
            img_tag = f'<img src="data:image/jpeg;base64,{b64}" alt="Frame at {html.escape(ts)}">'
        frames_html += f"""
<div class="frame">
  {img_tag}
  <div class="frame-info">
    <span class="timestamp">{html.escape(ts)}</span>
    <span class="reason">{html.escape(reason)}</span>
  </div>
</div>"""
else:
    frames_html = "<p><em>No key frames selected.</em></p>"

# Duration formatting
try:
    dur_int = int(float(duration))
    dur_fmt = f"{dur_int // 60}m {dur_int % 60}s"
except:
    dur_fmt = str(duration)

# Build HTML
generated = datetime.now().strftime("%Y-%m-%d %H:%M")
doc = f"""<!DOCTYPE html>
<html lang="he" dir="rtl">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)}</title>
<style>
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ font-family: -apple-system, Arial, sans-serif; background: #f8f9fa; color: #212529; padding: 2rem; direction: rtl; }}
  .container {{ max-width: 900px; margin: 0 auto; background: #fff; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,.1); overflow: hidden; }}
  header {{ background: #1a1a2e; color: #fff; padding: 2rem; }}
  header h1 {{ font-size: 1.6rem; margin-bottom: .5rem; }}
  header .meta {{ font-size: .9rem; opacity: .8; }}
  header a {{ color: #90cdf4; }}
  section {{ padding: 1.5rem 2rem; border-bottom: 1px solid #e9ecef; }}
  section h2 {{ font-size: 1.1rem; font-weight: 600; color: #495057; margin-bottom: 1rem; text-transform: uppercase; letter-spacing: .05em; }}
  p {{ line-height: 1.7; margin-bottom: .8rem; }}
  .frame {{ display: flex; gap: 1rem; margin-bottom: 1.2rem; align-items: flex-start; }}
  .frame img {{ width: 280px; min-width: 280px; border-radius: 6px; border: 1px solid #dee2e6; }}
  .frame-info {{ padding-top: .3rem; }}
  .timestamp {{ display: inline-block; background: #e3f2fd; color: #1565c0; padding: 2px 8px; border-radius: 4px; font-size: .85rem; font-family: monospace; margin-bottom: .4rem; }}
  .reason {{ display: block; color: #495057; font-size: .95rem; line-height: 1.5; }}
  pre {{ white-space: pre-wrap; font-size: .8rem; color: #495057; line-height: 1.5; max-height: 400px; overflow-y: auto; background: #f8f9fa; padding: 1rem; border-radius: 4px; border: 1px solid #dee2e6; }}
  footer {{ text-align: center; padding: 1rem; font-size: .8rem; color: #adb5bd; }}
  @media print {{ body {{ background: #fff; padding: 0; }} .container {{ box-shadow: none; }} pre {{ max-height: none; }} }}
</style>
</head>
<body>
<div class="container">
  <header>
    <h1>{html.escape(title)}</h1>
    <div class="meta">
      {html.escape(uploader)} &nbsp;·&nbsp; {dur_fmt}
      {f' &nbsp;·&nbsp; <a href="{html.escape(url)}">{html.escape(url[:60])}...</a>' if url else ''}
    </div>
  </header>

  <section>
    <h2>סיכום</h2>
    {summary_html}
  </section>

  <section>
    <h2>פריימים מרכזיים ({len(lines) if os.path.exists(manifest_file) else 0})</h2>
    {frames_html}
  </section>

  <section>
    <h2>תמלול מלא</h2>
    {transcript_html}
  </section>

  <footer>נוצר על ידי Video Analyzer &nbsp;·&nbsp; {generated}</footer>
</div>
</body>
</html>"""

with open(report_path, "w", encoding="utf-8") as f:
    f.write(doc)

size_kb = os.path.getsize(report_path) // 1024
print(f"  -> Report saved: {report_path} ({size_kb} KB)")
print(f"  -> Open in browser → File → Print → Save as PDF")
PYEOF

fi

# --- Final Summary ---
echo "=== Analysis Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Files:"
ls -lh "$OUTPUT_DIR/" 2>/dev/null | grep -v "^total" | grep -v "^d" | awk '{print "  " $NF " (" $5 ")"}'
echo ""
if [ -d "$OUTPUT_DIR/frames" ]; then
    FC=$(ls "$OUTPUT_DIR/frames/"*.jpg 2>/dev/null | wc -l)
    if [ "$FC" -gt 0 ]; then
        echo "  frames/ ($FC key frames)"
        if [ -f "$OUTPUT_DIR/frames/manifest.txt" ] && [ -s "$OUTPUT_DIR/frames/manifest.txt" ]; then
            echo ""
            echo "Frame manifest:"
            cat "$OUTPUT_DIR/frames/manifest.txt"
        fi
    fi
fi
if [ -f "$OUTPUT_DIR/summary.md" ]; then
    echo ""
    echo "--- Summary ---"
    cat "$OUTPUT_DIR/summary.md"
fi
if [ -f "$OUTPUT_DIR/report.html" ]; then
    echo ""
    echo "--- HTML Report ---"
    echo "  $OUTPUT_DIR/report.html"
    echo "  Open in browser → File → Print → Save as PDF"
fi
echo ""
echo "Done."
