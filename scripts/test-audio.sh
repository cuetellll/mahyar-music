#!/usr/bin/env bash
# =============================================================================
# Mahyar Music – test tone generator (Phase 1 voice-path verification)
# -----------------------------------------------------------------------------
# Runs INSIDE the container (railway ssh, docker exec, or as the container
# command override). Generates a short ORIGINAL test tone (5 s, 440 Hz sine,
# 48 kHz stereo) – no copyrighted material.
#
# Usage:
#   bash /app/scripts/test-audio.sh            # create if missing
#   bash /app/scripts/test-audio.sh --force    # regenerate
# =============================================================================
set -u

DATA_DIR="${DATA_DIR:-/data}"
BOT_ROOT="$DATA_DIR/bot"
MUSIC_DIR="$BOT_ROOT/music"
TARGET="$MUSIC_DIR/test-tone.wav"

mkdir -p "$MUSIC_DIR"

if [ -f "$TARGET" ] && [ "${1:-}" != "--force" ]; then
	echo "[INFO] Test tone already exists: $TARGET (use --force to regenerate)"
else
	if ! command -v ffmpeg >/dev/null 2>&1; then
		echo "[ERROR] FFmpeg was not found; the audio path cannot work." >&2
		exit 1
	fi
	if ffmpeg -hide_banner -loglevel error \
		-f lavfi -i "sine=frequency=440:duration=5" \
		-ar 48000 -ac 2 -c:a pcm_s16le \
		-y "$TARGET"; then
		echo "[INFO] Test tone generated: $TARGET (5 s, 440 Hz sine, 48 kHz stereo)"
	else
		echo "[ERROR] FFmpeg failed to generate the test tone." >&2
		exit 1
	fi
fi

# Keep ownership consistent when run as root via railway ssh.
if [ "$(id -u)" = "0" ] && id ts3ab >/dev/null 2>&1; then
	chown ts3ab:ts3ab "$TARGET"
fi

cat <<'INSTRUCTIONS'

Next steps (send these as TeamSpeak chat messages to the bot):
  !play test-tone.wav     # play the tone from the bot's music folder
  !volume 50              # adjust volume (0-100) if needed
  !whisper off            # only needed if audio.send_mode was changed to whisper

A human listener in the same channel MUST confirm hearing the tone –
"the bot is connected" alone does not prove the voice path.
INSTRUCTIONS
