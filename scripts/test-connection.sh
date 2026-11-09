#!/usr/bin/env bash
# =============================================================================
# Mahyar Music – network diagnostics (Phase 1)
# -----------------------------------------------------------------------------
# Runs INSIDE the container. Checks DNS resolution and TCP reachability of the
# TeamSpeak server ports.
#
# IMPORTANT – honest scope of this script:
#   TeamSpeak 3 VOICE traffic is UDP. A DNS hit or an open TCP port does NOT
#   prove that the voice path works. The only reliable proof is:
#     1. the bot's log shows "Successfully joined voice channel", and
#     2. a human in the channel hears the test tone (scripts/test-audio.sh).
# =============================================================================

set -u

TS3_HOST="${TS3_HOST:-}"
TS3_VOICE_PORT="${TS3_VOICE_PORT:-9987}"

if [ -z "$TS3_HOST" ]; then
	echo "[ERROR] TS3_HOST is not set." >&2
	exit 1
fi

tcp_probe() {
	# Returns 0 if a TCP connection to host:port succeeds within 5 s.
	local host="$1" port="$2"
	timeout 5 bash -c "exec 3<>/dev/tcp/${host}/${port}" 2>/dev/null
}

echo "=== Mahyar Music network diagnostics ==="
echo "Target: ${TS3_HOST}:${TS3_VOICE_PORT} (voice = UDP ${TS3_VOICE_PORT})"
echo

echo "--- 1) DNS resolution (3 attempts) ---"
resolved=""
for i in 1 2 3; do
	if resolved="$(getent hosts "$TS3_HOST" | head -n 1)"; then
		[ -n "$resolved" ] && break
	fi
	echo "  attempt $i failed, retrying in 2 s..."
	sleep 2
done
if [ -n "$resolved" ]; then
	echo "  PASS: $TS3_HOST -> $(echo "$resolved" | awk '{print $1}')"
else
	echo "  FAIL: DNS could not resolve '$TS3_HOST'."
	echo "  -> The bot cannot connect at all; check the hostname."
	exit 1
fi
echo

echo "--- 2) TCP port checks (informational only) ---"
for port in "$TS3_VOICE_PORT" 10011 30033; do
	if tcp_probe "$TS3_HOST" "$port"; then
		echo "  TCP $port: open"
	else
		echo "  TCP $port: closed/filtered"
	fi
done
cat <<NOTES

  NOTES (do not misread these results):
  - Voice port ${TS3_VOICE_PORT} is UDP-only; a closed TCP ${TS3_VOICE_PORT} is NORMAL
    and does NOT indicate a problem.
  - TCP 10011 (ServerQuery) / 30033 (file transfer) results are hints about
    general reachability only.
  - There is intentionally NO fake "UDP ping": the TS3 voice handshake is
    encrypted and cannot be meaningfully probed from a script.
NOTES
echo

echo "--- 3) Definitive voice-path test ---"
cat <<'STEPS'
  1. Watch the deployment logs: expect
       [INFO] TeamSpeak connection established. / joining channel messages
     from TS3AudioBot after startup.
  2. Confirm the bot named 'Mahyar Music' appears IN the configured channel.
  3. Run:  bash /app/scripts/test-audio.sh     (inside the container)
  4. In TeamSpeak chat send:  !play test-tone.wav
  5. A human in the channel must HEAR the 5 s tone.
STEPS
echo
echo "=== Diagnostics complete ==="
