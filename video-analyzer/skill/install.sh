#!/bin/bash
# Install the analyze-video skill into Claude Code
#
# Usage:
#   bash install.sh              # install to ~/.claude/commands/ (user-level, all projects)
#   bash install.sh --project    # install to .claude/commands/ (project-level, current repo only)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/analyze-video.md"

if [ ! -f "$SKILL_FILE" ]; then
    echo "Error: analyze-video.md not found in $SCRIPT_DIR" >&2
    exit 1
fi

if [ "$1" = "--project" ]; then
    TARGET_DIR=".claude/commands"
    echo "Installing to project-level: $TARGET_DIR/"
else
    TARGET_DIR="$HOME/.claude/commands"
    echo "Installing to user-level: $TARGET_DIR/"
fi

mkdir -p "$TARGET_DIR"
cp "$SKILL_FILE" "$TARGET_DIR/analyze-video.md"

echo "Done. Skill installed as /analyze-video"
echo ""
echo "Usage in Claude Code:"
echo "  /analyze-video https://www.loom.com/share/abc123"
echo "  /analyze-video https://youtu.be/xyz --language en"
