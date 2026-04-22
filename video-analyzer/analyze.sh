#!/bin/bash
# Video Analyzer — Full pipeline: download → metadata → audio extract → transcribe → key frames
#
# Usage:
#   ./analyze.sh <URL> [--output-dir DIR] [--language LANG] [--no-transcribe] [--no-frames]
#
# Examples:
#   ./analyze.sh "https://www.loom.com/share/abc123"
#   ./analyze.sh "https://youtu.be/xyz" --language en --output-dir /tmp/out
#   ./analyze.sh "https://www.loom.com/share/abc123" --no-transcribe

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YT_DLP="$SCRIPT_DIR/bin/yt-dlp"
TRANSCRIBE="$SCRIPT_DIR/transcribe.sh"
FFMPEG="${FFMPEG_PATH:-$(command -v ffmpeg 2>/dev/null || echo "$HOME/.local/bin/ffmpeg")}"

# --- Defaults ---
LANGUAGE="he"
OUTPUT_DIR=""
DO_TRANSCRIBE=1
DO_FRAMES=1
URL=""

# --- Parse args ---
while [ $# -gt 0 ]; do
    case "$1" in
        --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
        --language)    LANGUAGE="$2"; shift 2 ;;
        --no-transcribe) DO_TRANSCRIBE=0; shift ;;
        --no-frames)   DO_FRAMES=0; shift ;;
        -h|--help)
            echo "Usage: $0 <URL> [--output-dir DIR] [--language LANG] [--no-transcribe] [--no-frames]"
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
    echo "Usage: $0 <URL> [--output-dir DIR] [--language LANG] [--no-transcribe] [--no-frames]" >&2
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
    # Extract video ID from URL for directory name
    VIDEO_ID=$(echo "$URL" | grep -oP '[a-f0-9]{32}|[a-zA-Z0-9_-]{11}' | head -1 || echo "video")
    OUTPUT_DIR="/home/agent/agents/github-agent/video-analyze/output/$VIDEO_ID"
fi
mkdir -p "$OUTPUT_DIR/frames"

echo "=== Video Analyzer ==="
echo "URL: $URL"
echo "Output: $OUTPUT_DIR"
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
    echo "  -> Title: $TITLE"
    echo "  -> Duration: ${DURATION}s"
else
    echo "  -> Metadata extraction failed (non-critical)."
    DURATION=$("$FFMPEG" -i "$VIDEO_FILE" 2>&1 | grep Duration | awk '{print $2}' | tr -d , || echo "?")
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

# --- Step 4: Transcribe (with timestamps) ---
echo "[4/5] Transcribing..."
TRANSCRIPT_FILE="$OUTPUT_DIR/transcript.txt"
if [ "$DO_TRANSCRIBE" -eq 0 ]; then
    echo "  -> Skipped."
elif [ -f "$TRANSCRIPT_FILE" ]; then
    echo "  -> Already transcribed, skipping."
else
    if [ -x "$TRANSCRIBE" ]; then
        "$TRANSCRIBE" "$AUDIO_FILE" --language "$LANGUAGE" > "$TRANSCRIPT_FILE" 2>/dev/null || {
            echo "  -> Transcription failed." >&2
            DO_TRANSCRIBE=0
        }
        if [ "$DO_TRANSCRIBE" -eq 1 ] && [ -s "$TRANSCRIPT_FILE" ]; then
            WORD_COUNT=$(wc -w < "$TRANSCRIPT_FILE")
            echo "  -> Done: $WORD_COUNT words (with timestamps)"
        fi
    else
        echo "  -> transcribe.sh not found at $TRANSCRIBE, skipping."
    fi
fi
echo ""

# --- Step 5: Extract key frames (scene-change detection) ---
echo "[5/5] Extracting key frames..."
if [ "$DO_FRAMES" -eq 0 ]; then
    echo "  -> Skipped."
else
    MANIFEST="$OUTPUT_DIR/frames/manifest.txt"
    FRAME_COUNT=$(ls "$OUTPUT_DIR/frames/"*.jpg 2>/dev/null | wc -l)
    if [ "$FRAME_COUNT" -gt 0 ]; then
        echo "  -> Already extracted ($FRAME_COUNT frames), skipping."
    else
        # Strategy: scene-change detection with 12% threshold.
        # Extracts only frames that differ significantly from the previous one.
        # Then enforces minimum 3-second gap to avoid bursts.
        #
        # Filenames encode the timestamp: frame_01m25s.jpg
        # manifest.txt maps timestamp → filename for sync with transcript.

        # Step 5a: Extract scene-change frames + collect their timestamps
        SCENE_LOG="$OUTPUT_DIR/frames/.scene_detect.log"
        "$FFMPEG" -i "$VIDEO_FILE" \
            -vf "select='gt(scene,0.12)',showinfo" \
            -vsync vfr -q:v 3 \
            "$OUTPUT_DIR/frames/raw_%06d.jpg" -y 2>&1 \
            | grep "showinfo" > "$SCENE_LOG" 2>/dev/null || true

        RAW_COUNT=$(ls "$OUTPUT_DIR/frames/raw_"*.jpg 2>/dev/null | wc -l)
        rm -f "$MANIFEST"

        if [ "$RAW_COUNT" -gt 0 ]; then
            # Parse timestamps from showinfo log: pts_time:123.456
            TIMESTAMPS=$(grep -oP 'pts_time:\K[0-9.]+' "$SCENE_LOG" 2>/dev/null || true)

            if [ -n "$TIMESTAMPS" ]; then
                # Rename with timestamps + enforce 3s minimum gap
                PREV_SECS=-10
                IDX=1
                for RAW_TS in $TIMESTAMPS; do
                    SECS=$(printf "%.0f" "$RAW_TS")

                    # Enforce minimum 3-second gap
                    DIFF=$((SECS - PREV_SECS))
                    if [ "$DIFF" -lt 3 ] && [ "$PREV_SECS" -ge 0 ]; then
                        rm -f "$OUTPUT_DIR/frames/raw_$(printf '%06d' $IDX).jpg"
                        IDX=$((IDX + 1))
                        continue
                    fi

                    RAW_FILE="$OUTPUT_DIR/frames/raw_$(printf '%06d' $IDX).jpg"
                    if [ ! -f "$RAW_FILE" ]; then
                        IDX=$((IDX + 1))
                        continue
                    fi

                    MINS=$((SECS / 60))
                    RSECS=$((SECS % 60))
                    TS=$(printf "%02dm%02ds" "$MINS" "$RSECS")
                    PRETTY=$(printf "%02d:%02d" "$MINS" "$RSECS")

                    mv "$RAW_FILE" "$OUTPUT_DIR/frames/frame_${TS}.jpg"
                    echo "$PRETTY  frame_${TS}.jpg" >> "$MANIFEST"

                    PREV_SECS=$SECS
                    IDX=$((IDX + 1))
                done
            else
                # Timestamps not parsed — rename sequentially
                IDX=0
                for F in "$OUTPUT_DIR/frames/raw_"*.jpg; do
                    [ -f "$F" ] || continue
                    SECS=$((IDX * 5))
                    MINS=$((SECS / 60))
                    RSECS=$((SECS % 60))
                    TS=$(printf "%02dm%02ds" "$MINS" "$RSECS")
                    PRETTY=$(printf "%02d:%02d" "$MINS" "$RSECS")
                    mv "$F" "$OUTPUT_DIR/frames/frame_${TS}.jpg"
                    echo "$PRETTY  frame_${TS}.jpg" >> "$MANIFEST"
                    IDX=$((IDX + 1))
                done
            fi
        else
            # Fallback: scene detection produced 0 frames — use interval sampling (1 per 5 seconds)
            echo "  -> Scene detection found 0 changes, falling back to 1 frame / 5 seconds..."
            "$FFMPEG" -i "$VIDEO_FILE" \
                -vf "fps=1/5" -q:v 3 \
                "$OUTPUT_DIR/frames/raw_%06d.jpg" -y 2>/dev/null

            IDX=0
            for F in "$OUTPUT_DIR/frames/raw_"*.jpg; do
                [ -f "$F" ] || continue
                SECS=$((IDX * 5))
                MINS=$((SECS / 60))
                RSECS=$((SECS % 60))
                TS=$(printf "%02dm%02ds" "$MINS" "$RSECS")
                PRETTY=$(printf "%02d:%02d" "$MINS" "$RSECS")
                mv "$F" "$OUTPUT_DIR/frames/frame_${TS}.jpg"
                echo "$PRETTY  frame_${TS}.jpg" >> "$MANIFEST"
                IDX=$((IDX + 1))
            done
        fi

        # Clean up
        rm -f "$OUTPUT_DIR/frames/raw_"*.jpg "$SCENE_LOG"

        FRAME_COUNT=$(ls "$OUTPUT_DIR/frames/"*.jpg 2>/dev/null | wc -l)
        echo "  -> Done: $FRAME_COUNT key frames (scene-change detection, min 3s gap)"
        if [ -f "$MANIFEST" ]; then
            echo "  -> Manifest: $MANIFEST"
        fi
    fi
fi
echo ""

# --- Summary ---
echo "=== Analysis Complete ==="
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Files:"
ls -lh "$OUTPUT_DIR/" | grep -v "^total" | grep -v "^d" | awk '{print "  " $NF " (" $5 ")"}'
echo ""
if [ -d "$OUTPUT_DIR/frames" ]; then
    FC=$(ls "$OUTPUT_DIR/frames/"*.jpg 2>/dev/null | wc -l)
    echo "  frames/ ($FC key frames)"
    if [ -f "$OUTPUT_DIR/frames/manifest.txt" ]; then
        echo "  manifest.txt — timestamp → frame mapping"
    fi
fi
echo ""
echo "Done."
