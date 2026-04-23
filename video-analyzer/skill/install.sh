#!/bin/bash
# Install video-analyzer skills into Claude Code
#
# Skills installed:
#   /analyze-video  — full analysis (frames + summary)
#   /video-short    — quick summary only, no frames
#   /video-pdf      — full analysis + HTML report (open in browser → Save as PDF)
#
# Usage:
#   bash install.sh              # install to ~/.claude/skills/ (user-level, all projects)
#   bash install.sh --project    # install to .claude/skills/ (project-level, current repo only)
#   bash install.sh --legacy     # install to ~/.claude/commands/ (legacy flat-file format, analyze-video only)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS=("analyze-video" "video-short" "video-pdf")

if [ "$1" = "--project" ]; then
    TARGET_BASE=".claude/skills"
    echo "Installing to project-level: $TARGET_BASE/"
elif [ "$1" = "--legacy" ]; then
    # Legacy: copy analyze-video.md to commands/ (only main skill)
    TARGET_DIR="${HOME}/.claude/commands"
    mkdir -p "$TARGET_DIR"
    cp "$SCRIPT_DIR/analyze-video.md" "$TARGET_DIR/analyze-video.md"
    echo "Installed /analyze-video (legacy) to $TARGET_DIR/"
    exit 0
else
    TARGET_BASE="${HOME}/.claude/skills"
    echo "Installing to user-level: $TARGET_BASE/"
fi

mkdir -p "$TARGET_BASE"

for SKILL in "${SKILLS[@]}"; do
    SRC="$SCRIPT_DIR/$SKILL/SKILL.md"
    if [ ! -f "$SRC" ]; then
        echo "Warning: $SRC not found — skipping $SKILL" >&2
        continue
    fi
    DEST="$TARGET_BASE/$SKILL"
    mkdir -p "$DEST"
    cp "$SRC" "$DEST/SKILL.md"
    echo "  Installed /$SKILL -> $DEST/SKILL.md"
done

echo ""
echo "Done. Skills installed:"
echo "  /analyze-video  — full analysis (frames + summary)"
echo "  /video-short    — quick summary only"
echo "  /video-pdf      — full analysis + HTML report"
echo ""
echo "Usage in Claude Code:"
echo "  /analyze-video https://www.loom.com/share/abc123"
echo "  /video-short   https://youtu.be/xyz --language en"
echo "  /video-pdf     https://www.loom.com/share/abc123"
