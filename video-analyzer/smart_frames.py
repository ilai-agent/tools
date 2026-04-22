#!/usr/bin/env python3
"""
Smart frame extractor — extracts video frames only at timestamps where the speaker
uses visual reference phrases ("look at this", "תראה", "כאן", etc.).

Usage:
    python3 smart_frames.py <transcript.srt> <video.mp4> <output_frames_dir> [ffmpeg_bin]
"""

import re
import sys
import os
import subprocess


def parse_srt_time(ts: str) -> float:
    """Convert SRT timestamp to seconds: '00:01:23,456' -> 83.456"""
    ts = ts.strip()
    h, m, s_ms = ts.split(':')
    s, ms = s_ms.split(',')
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def parse_srt(srt_file: str):
    """Parse SRT file. Returns list of (start_secs, end_secs, text)."""
    entries = []
    with open(srt_file, encoding='utf-8') as f:
        content = f.read()

    blocks = re.split(r'\n{2,}', content.strip())
    for block in blocks:
        lines = block.strip().split('\n')
        if len(lines) < 3:
            continue
        try:
            time_line = lines[1]
            start_str, end_str = time_line.split(' --> ')
            start = parse_srt_time(start_str)
            end = parse_srt_time(end_str)
            text = ' '.join(lines[2:])
            entries.append((start, end, text))
        except Exception:
            continue
    return entries


# Phrases that indicate the speaker is pointing at something on screen
VISUAL_PATTERNS = [
    # Hebrew
    r'תראה',          # "look" / "see"
    r'תסתכל',         # "look at"
    r'הנה',           # "here" / "look here"
    r'\bכאן\b',       # "here"
    r'\bפה\b',        # "here"
    r'כמו שאני',      # "like I'm doing"
    r'אתה רואה',      # "you see"
    r'אני רואה',      # "I see" (pointing)
    r'אתה מבין',      # "you understand" (demonstrating)
    r'תראו',          # "look" (plural)
    r'תראה לי',       # "show me"
    r'ככה',           # "like this"
    r'\bכך\b',        # "thus / like this"
    r'רגע,?\s+תראה',  # "wait, look"
    r'עכשיו,?\s+תראה',  # "now look"
    r'אתה רואה\s+כאן',
    r'אתה רואה\s+פה',
    # English
    r'\blook at\b',
    r'\bsee this\b',
    r'\bright here\b',
    r'\bover here\b',
    r'\bwatch\b',
    r'\blike this\b',
    r'\bhere\b',
]


def has_visual_cue(text: str) -> bool:
    for pat in VISUAL_PATTERNS:
        if re.search(pat, text, re.IGNORECASE):
            return True
    return False


def extract_frame(video_file: str, timestamp_secs: float, output_path: str, ffmpeg_bin: str = 'ffmpeg') -> bool:
    h = int(timestamp_secs // 3600)
    m = int((timestamp_secs % 3600) // 60)
    s = timestamp_secs % 60
    ts_str = f"{h:02d}:{m:02d}:{s:06.3f}"
    cmd = [ffmpeg_bin, '-ss', ts_str, '-i', video_file, '-vframes', '1', '-q:v', '2', output_path, '-y']
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0 and os.path.exists(output_path)


def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <transcript.srt> <video.mp4> <output_frames_dir> [ffmpeg_bin]", file=sys.stderr)
        sys.exit(1)

    srt_file   = sys.argv[1]
    video_file = sys.argv[2]
    output_dir = sys.argv[3]
    ffmpeg_bin = sys.argv[4] if len(sys.argv) > 4 else 'ffmpeg'

    os.makedirs(output_dir, exist_ok=True)

    if not os.path.exists(srt_file):
        print(f"Error: SRT file not found: {srt_file}", file=sys.stderr)
        sys.exit(1)

    entries = parse_srt(srt_file)
    if not entries:
        print("  -> No subtitle entries found in SRT.")
        sys.exit(0)

    manifest_lines = []
    prev_extracted = -10.0  # enforce minimum gap between frames

    MIN_GAP_SECS = 3.0

    for start, end, text in entries:
        if not has_visual_cue(text):
            continue
        if start - prev_extracted < MIN_GAP_SECS:
            continue

        mins = int(start // 60)
        secs = int(start % 60)
        ts_label = f"{mins:02d}m{secs:02d}s"
        pretty   = f"{mins:02d}:{secs:02d}"
        frame_path = os.path.join(output_dir, f"frame_{ts_label}.jpg")

        if extract_frame(video_file, start, frame_path, ffmpeg_bin):
            excerpt = text[:80].replace('\n', ' ')
            manifest_lines.append(f"{pretty}  frame_{ts_label}.jpg  # {excerpt}")
            print(f"  -> [{pretty}] {excerpt}")
            prev_extracted = start
        else:
            print(f"  -> [{pretty}] frame extraction failed, skipping.", file=sys.stderr)

    if manifest_lines:
        manifest_file = os.path.join(output_dir, 'manifest.txt')
        with open(manifest_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(manifest_lines) + '\n')
        print(f"  -> Manifest saved: {manifest_file}")

    print(f"  -> Total frames extracted: {len(manifest_lines)}")


if __name__ == '__main__':
    main()
