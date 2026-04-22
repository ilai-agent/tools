#!/bin/bash
# Whisper transcription wrapper using whisper.cpp
#
# Usage:
#   ./transcribe.sh <audio_file> [--language he|en] [--translate]
#
# Examples:
#   ./transcribe.sh audio.wav --language he
#   ./transcribe.sh audio.ogg --language en --translate

set -e

WHISPER_BIN="${WHISPER_BIN:-$HOME/whisper.cpp/build/bin/whisper-cli}"
MODELS_DIR="${WHISPER_MODELS:-$HOME/whisper.cpp/models}"
DEFAULT_MODEL="ggml-small.bin"
FFMPEG="${FFMPEG_PATH:-$(command -v ffmpeg 2>/dev/null || echo "$HOME/.local/bin/ffmpeg")}"

# Validate whisper binary
if [ ! -f "$WHISPER_BIN" ]; then
    echo "Error: Whisper binary not found at $WHISPER_BIN" >&2
    echo "Set WHISPER_BIN env var to override." >&2
    exit 1
fi

# Validate model
if [ ! -f "$MODELS_DIR/$DEFAULT_MODEL" ]; then
    echo "Error: Model not found at $MODELS_DIR/$DEFAULT_MODEL" >&2
    echo "Set WHISPER_MODELS env var to override." >&2
    exit 1
fi

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <audio_file> [--language he|en] [--translate]" >&2
    exit 1
fi

AUDIO_FILE="$1"
LANGUAGE="en"
TRANSLATE=0

shift
while [ $# -gt 0 ]; do
    case "$1" in
        --language) LANGUAGE="$2"; shift 2 ;;
        --translate) TRANSLATE=1; shift ;;
        *) echo "Unknown option: $1" >&2; shift ;;
    esac
done

# Validate input file
if [ ! -f "$AUDIO_FILE" ]; then
    echo "Error: Audio file not found: $AUDIO_FILE" >&2
    exit 1
fi

# Convert to WAV 16kHz mono if needed (whisper.cpp requires this)
EXT="${AUDIO_FILE##*.}"
if [ "$EXT" != "wav" ]; then
    TEMP_WAV=$(mktemp /tmp/whisper_XXXXXX.wav)
    trap "rm -f $TEMP_WAV" EXIT
    "$FFMPEG" -i "$AUDIO_FILE" -ar 16000 -ac 1 -acodec pcm_s16le "$TEMP_WAV" -y 2>/dev/null
    AUDIO_FILE="$TEMP_WAV"
fi

# Build whisper command
WHISPER_OPTS="-m $MODELS_DIR/$DEFAULT_MODEL -l $LANGUAGE -f $AUDIO_FILE"

if [ "$TRANSLATE" -eq 1 ]; then
    WHISPER_OPTS="$WHISPER_OPTS --translate"
fi

# Execute
"$WHISPER_BIN" $WHISPER_OPTS 2>/dev/null
