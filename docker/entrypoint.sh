#!/usr/bin/env bash
# =============================================================================
# Mahyar Music – container entrypoint
# -----------------------------------------------------------------------------
# Responsibilities:
#   1. Prepare the persistent storage layout under DATA_DIR (/data on Railway).
#   2. Validate the environment configuration and the TeamSpeak identity file
#      (fail fast with clear, secret-free error messages).
#   3. Generate the TS3AudioBot 0.12.0 configuration from environment
#      variables. Generation is idempotent: the files are only rewritten when
#      the managed values actually change, so values the bot writes back at
#      runtime (identity offset, hashed passwords, bot_group_id) survive
#      restarts.
#   4. Run the bot as a dedicated non-root user with signal forwarding and a
#      bounded crash-restart loop. The outer restart policy is Railway's job
#      (railway.json: ON_FAILURE, 10 retries).
#
# Engine: TS3AudioBot 0.12.0 (self-contained linux-x64 release build)
# Docs:   .env.example, docs/RAILWAY_DEPLOYMENT.md, docs/SECURITY.md
# =============================================================================
set -u

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
TS3AB_VERSION="0.12.0"
CONFIG_TEMPLATE_VERSION="mahyar-music-config-1"

APP_USER="ts3ab"
APP_GROUP="ts3ab"
APP_HOME="/var/lib/ts3ab"
# Internals overridable for local testing of the generation logic only.
BOT_INSTALL_DIR="${MAHYAR_BOT_INSTALL_DIR:-/opt/ts3audiobot}"
APP_DIR="${MAHYAR_APP_DIR:-/app}"
NLOG_TEMPLATE="$APP_DIR/nlog.config.template"

DATA_DIR="${DATA_DIR:-/data}"
BOT_ROOT="$DATA_DIR/bot"
SECRETS_DIR="$DATA_DIR/secrets"
TS3_IDENTITY_FILE="${TS3_IDENTITY_FILE:-$SECRETS_DIR/identity.ini}"
BOT_NAME="mahyar-music"

TS3_HOST="${TS3_HOST:-}"
TS3_VOICE_PORT="${TS3_VOICE_PORT:-9987}"
TS3_NICKNAME="${TS3_NICKNAME:-Mahyar Music}"
TS3_CHANNEL_ID="${TS3_CHANNEL_ID:-}"
TS3_CHANNEL_PATH="${TS3_CHANNEL_PATH:-}"
TS3_SERVER_PASSWORD="${TS3_SERVER_PASSWORD:-}"
TS3_CHANNEL_PASSWORD="${TS3_CHANNEL_PASSWORD:-}"
LOG_LEVEL="${LOG_LEVEL:-Information}"
MAHYAR_BOOTSTRAP="${MAHYAR_BOOTSTRAP:-0}"

# Private bits must never leak into the logs; keep a restrictive umask so all
# generated files (including the identity-carrying bot.toml) are 600.
umask 077

# -----------------------------------------------------------------------------
# Logging helpers (never log secrets)
# -----------------------------------------------------------------------------
mm_info() { echo "[INFO]  [Mahyar Music] $*"; }
mm_warn() { echo "[WARN]  [Mahyar Music] $*" >&2; }
mm_die()  { echo "[ERROR] [Mahyar Music] $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Shared validation functions (identity parsing lives here too, so the same
# logic can be reused by scripts/validate-config.sh without the container)
# -----------------------------------------------------------------------------
# shellcheck source=scripts/validate-config.sh
source "$APP_DIR/scripts/validate-config.sh"

# -----------------------------------------------------------------------------
# TOML helpers
# -----------------------------------------------------------------------------
toml_escape() {
	# Escape backslashes and double quotes for a TOML basic string.
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	printf '%s' "$s"
}

# -----------------------------------------------------------------------------
# Requirement checks
# -----------------------------------------------------------------------------
# Checks host/port/channel/identity and appends problems to the global
# MM_MISSING variable. Deliberately runs in the MAIN shell (never inside a
# command substitution) so the MM_IDENTITY_KEY exported by mm_identity_read
# stays available for config generation. Empty MM_MISSING = config complete.
mm_check_requirements() {
	MM_MISSING=""
	[ -n "$TS3_HOST" ] || MM_MISSING+="TS3_HOST is not set. "
	if ! [[ "$TS3_VOICE_PORT" =~ ^[0-9]+$ ]] || [ "$TS3_VOICE_PORT" -lt 1 ] || [ "$TS3_VOICE_PORT" -gt 65535 ]; then
		MM_MISSING+="TS3_VOICE_PORT must be an integer between 1 and 65535 (got: '$TS3_VOICE_PORT'). "
	fi
	# A predefined target channel is mandatory (spec: one fixed channel).
	# Both may be set; the stable channel id wins (see mm_resolve_channel).
	if [ -z "$TS3_CHANNEL_ID" ] && [ -z "$TS3_CHANNEL_PATH" ]; then
		MM_MISSING+="Either TS3_CHANNEL_ID or TS3_CHANNEL_PATH must be set. "
	fi
	if [ -n "$TS3_CHANNEL_ID" ] && ! [[ "$TS3_CHANNEL_ID" =~ ^[0-9]+$ ]]; then
		MM_MISSING+="TS3_CHANNEL_ID must be a numeric TeamSpeak channel id (got: '$TS3_CHANNEL_ID'). "
	fi
	# Identity: must exist, be readable and have a known format. The key is
	# kept in MM_IDENTITY_KEY (memory only) and is never printed.
	if [ ! -f "$TS3_IDENTITY_FILE" ]; then
		MM_MISSING+="Identity file not found at TS3_IDENTITY_FILE=$TS3_IDENTITY_FILE. "
	elif [ ! -r "$TS3_IDENTITY_FILE" ]; then
		MM_MISSING+="Identity file is not readable at TS3_IDENTITY_FILE=$TS3_IDENTITY_FILE. "
	elif ! mm_identity_read "$TS3_IDENTITY_FILE"; then
		MM_MISSING+="Identity file is invalid or has an unsupported format. "
	fi
	return 0
}

# Resolves the channel setting: prefer the stable numeric channel id
# (TS3AudioBot 0.12.0 documents channel = "/<id>" as a stable identifier).
mm_resolve_channel() {
	if [ -n "$TS3_CHANNEL_ID" ]; then
		if [ -n "$TS3_CHANNEL_PATH" ]; then
			mm_info "Both TS3_CHANNEL_ID and TS3_CHANNEL_PATH are set; using the stable channel id (/$TS3_CHANNEL_ID)."
		fi
		printf '/%s' "$TS3_CHANNEL_ID"
	else
		printf '%s' "$TS3_CHANNEL_PATH"
	fi
}

mm_build_address() {
	# If the host already carries a port, keep it as-is (and inform the owner).
	case "$TS3_HOST" in
		*:*)
			if [ "${TS3_VOICE_PORT:-9987}" != "9987" ]; then
				mm_warn "TS3_HOST already contains a port; ignoring TS3_VOICE_PORT=$TS3_VOICE_PORT."
			fi
			printf '%s' "$TS3_HOST"
			;;
		*)
			printf '%s:%s' "$TS3_HOST" "$TS3_VOICE_PORT"
			;;
	esac
}

# -----------------------------------------------------------------------------
# Bootstrap mode: keep the container alive (sleep) while the owner uploads the
# identity file through `railway ssh` (see docs/RAILWAY_DEPLOYMENT.md).
# -----------------------------------------------------------------------------
mm_bootstrap_wait() {
	mm_warn "MAHYAR_BOOTSTRAP=1 - bootstrap mode active."
	mm_warn "The container stays alive so you can upload the identity file:"
	mm_warn "  railway ssh --service <service-name>"
	mm_warn "  mkdir -p $SECRETS_DIR"
	mm_warn "  cat > $TS3_IDENTITY_FILE <<'EOF' ... (paste the exported identity ini) ... EOF"
	mm_warn "Then set MAHYAR_BOOTSTRAP=0 (or remove it) and redeploy."
	while :; do
		mm_check_requirements
		if [ -z "$MM_MISSING" ]; then
			mm_info "Bootstrap complete: all requirements are satisfied. Continuing startup."
			return 0
		fi
		mm_info "Bootstrap: still waiting for manual setup ($MM_MISSING)"
		sleep 300
	done
}

# -----------------------------------------------------------------------------
# Config generation (idempotent via fingerprint)
# -----------------------------------------------------------------------------
mm_fingerprint() {
	printf '%s\n' \
		"$CONFIG_TEMPLATE_VERSION" \
		"$TS3AB_VERSION" \
		"$DATA_DIR" \
		"$TS3_HOST" \
		"$TS3_VOICE_PORT" \
		"$TS3_NICKNAME" \
		"$TS3_CHANNEL_ID" \
		"$TS3_CHANNEL_PATH" \
		"$TS3_SERVER_PASSWORD" \
		"$TS3_CHANNEL_PASSWORD" \
		"$MM_IDENTITY_KEY" \
		| sha256sum | cut -d' ' -f1
}

mm_generate_root_config() {
	local bot_root="$BOT_ROOT"
	cat > "$bot_root/ts3audiobot.toml" <<EOF
# =============================================================================
# ts3audiobot.toml - generated by the Mahyar Music entrypoint
# Engine: TS3AudioBot $TS3AB_VERSION (https://github.com/Splamy/TS3AudioBot)
# Managed keys come from environment variables and are only rewritten when
# those values change. This file contains no secrets; the bot identity lives
# in bots/$BOT_NAME/bot.toml (chmod 600).
# =============================================================================
[configs]
bots_path = "$bot_root/bots"
send_stats = false

[db]
path = "$bot_root/ts3audiobot.db"

[factories]
media = { path = "$bot_root/music" }

[tools]
ffmpeg = { path = "ffmpeg" }

[rights]
path = "$bot_root/rights.toml"

[plugins]
path = "$bot_root/plugins"

[web]
# Disabled in Phase 1 (worker deployment, no public ports).
# Enable both for the Phase 4 web dashboard; see docs/RAILWAY_DEPLOYMENT.md.
hosts = ["localhost"]
port = 58913

[web.api]
enabled = false

[web.interface]
enabled = false

[bot]
# Defaults for all bots; per-bot overrides live in bots/$BOT_NAME/bot.toml.
language = "en"
run = false
generate_status_avatar = false
set_status_description = true
EOF
}

mm_generate_bot_config() {
	local bot_root="$BOT_ROOT"
	local address channel
	address="$(mm_build_address)"
	channel="$(mm_resolve_channel)"

	{
		cat <<EOF
# =============================================================================
# bot.toml ($BOT_NAME) - generated by the Mahyar Music entrypoint
# ||| CONTAINS THE PRIVATE TEAMSPEAK IDENTITY - DO NOT COMMIT OR SHARE |||
# Managed keys are only rewritten when the environment variables change;
# values the bot writes back at runtime (identity offset, hashed passwords)
# are preserved across restarts.
# =============================================================================
run = true
language = "en"

[connect]
address = "$(toml_escape "$address")"
name = "$(toml_escape "$TS3_NICKNAME")"
channel = "$(toml_escape "$channel")"
EOF

		if [ -n "$TS3_SERVER_PASSWORD" ]; then
			cat <<EOF

[connect.server_password]
pw = "$(toml_escape "$TS3_SERVER_PASSWORD")"
hashed = false
autohash = true
EOF
		fi

		if [ -n "$TS3_CHANNEL_PASSWORD" ]; then
			cat <<EOF

[connect.channel_password]
pw = "$(toml_escape "$TS3_CHANNEL_PASSWORD")"
hashed = false
autohash = true
EOF
		fi

		cat <<EOF

[connect.identity]
# ||| DO NOT MAKE THIS KEY PUBLIC |||
# Imported TeamSpeak3 client identity (TS3AudioBot 0.12.0 documents that
# "connect.identity.key" accepts an imported teamspeak3 identity).
key = "$(toml_escape "$MM_IDENTITY_KEY")"
offset = 0
level = -1

[audio]
# "voice" sends normal channel voice; the whisper default is overridden so
# the bot is audible to everyone in the channel without '!subscribe'.
send_mode = "voice"
bitrate = 48

[audio.volume]
default = 50
min = 25
max = 75

[reconnect]
# Built-in automatic reconnection of TS3AudioBot 0.12.0 (defaults kept).
ontimeout = ["1s", "2s", "5s", "10s", "30s", "1m", "5m", "repeat last"]
onkick = []
onban = []
onerror = ["30s", "repeat last"]
onshutdown = ["5m"]
EOF
	} > "$bot_root/bots/$BOT_NAME/bot.toml"
}

mm_generate_nlog() {
	local minlevel
	case "${LOG_LEVEL,,}" in
		trace)       minlevel="Trace" ;;
		debug)       minlevel="Debug" ;;
		information) minlevel="Info" ;;
		warning)     minlevel="Warn" ;;
		error)       minlevel="Error" ;;
		fatal)       minlevel="Fatal" ;;
		*)
			mm_warn "Unknown LOG_LEVEL '$LOG_LEVEL'; using 'Information'."
			minlevel="Info"
			;;
	esac
	sed "s/__MINLEVEL__/$minlevel/g" "$NLOG_TEMPLATE" > "$BOT_ROOT/NLog.config"
	# NLog also probes the executable directory; place a copy there as well.
	sed "s/__MINLEVEL__/$minlevel/g" "$NLOG_TEMPLATE" > "$BOT_INSTALL_DIR/NLog.config"
}

mm_generate_configs() {
	local fingerprint_file="$BOT_ROOT/.mahyar-managed.sha256"
	local current_fingerprint stored_fingerprint
	current_fingerprint="$(mm_fingerprint)"

	if [ -f "$fingerprint_file" ]; then
		stored_fingerprint="$(cat "$fingerprint_file")"
	else
		stored_fingerprint=""
	fi

	if [ "$current_fingerprint" = "$stored_fingerprint" ]; then
		mm_info "Configuration is up to date (no managed values changed)."
	else
		if [ -z "$stored_fingerprint" ]; then
			mm_info "Generating TS3AudioBot configuration for the first time..."
		else
			mm_info "Managed configuration values changed; regenerating configuration..."
		fi
		mm_generate_root_config
		mm_generate_bot_config
		printf '%s\n' "$current_fingerprint" > "$fingerprint_file"
		mm_info "Configuration generated."
	fi
	mm_generate_nlog
}

mm_prepare_storage() {
	mkdir -p "$BOT_ROOT/bots/$BOT_NAME" "$BOT_ROOT/music" "$BOT_ROOT/plugins" "$SECRETS_DIR"
}

mm_fix_permissions() {
	chown -R "$APP_USER:$APP_GROUP" "$DATA_DIR"
	chmod 600 "$TS3_IDENTITY_FILE" 2>/dev/null || true
	chmod 600 "$BOT_ROOT/ts3audiobot.toml" "$BOT_ROOT/bots/$BOT_NAME/bot.toml" 2>/dev/null || true
}

mm_generate_test_tone() {
	# Short original test tone (5 s, 440 Hz sine, 48 kHz stereo) for the
	# initial voice-path verification. No copyrighted material is used.
	local target="$BOT_ROOT/music/test-tone.wav"
	if [ -f "$target" ]; then
		return 0
	fi
	if command -v ffmpeg >/dev/null 2>&1; then
		if ffmpeg -hide_banner -loglevel error \
			-f lavfi -i "sine=frequency=440:duration=5" \
			-ar 48000 -ac 2 -c:a pcm_s16le \
			-y "$target"; then
			mm_info "Test tone generated: music/test-tone.wav (5 s, 440 Hz sine)."
		else
			mm_die "FFmpeg could not generate the test tone."
		fi
	else
		mm_die "FFmpeg was not found; the audio path cannot work."
	fi
}

# -----------------------------------------------------------------------------
# Bot supervision
# -----------------------------------------------------------------------------
BOT_CHILD_PID=""
SHUTDOWN_REQUESTED=0

mm_on_signal() {
	SHUTDOWN_REQUESTED=1
	if [ -n "$BOT_CHILD_PID" ]; then
		# TS3AudioBot handles SIGINT (Ctrl+C) gracefully (see upstream FAQ:
		# systemd unit uses KillSignal=SIGINT); forward SIGTERM as SIGINT.
		kill -INT "$BOT_CHILD_PID" 2>/dev/null || true
	fi
}
trap mm_on_signal INT TERM

mm_run_bot() {
	local exit_code=0
	local crash_restarts=0
	local last_start_ts=0
	local now backoff

	while :; do
		mm_info "Starting TS3AudioBot $TS3AB_VERSION..."
		now="$(date +%s)"
		if [ $((now - last_start_ts)) -gt 300 ]; then
			crash_restarts=0
		fi

		cd "$BOT_ROOT"
		# DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1: the pinned TS3AudioBot 0.12.0
		# build targets .NET Core 3.1, whose hardcoded ICU version list predates
		# Debian 12's ICU 72 -> without this flag it FailFasts at startup
		# ("Couldn't find a valid ICU package"). The bot does not need locale
		# formatting; upstream recommends invariant mode for such environments.
		gosu "$APP_USER:$APP_GROUP" env HOME="$APP_HOME" LANG=C.UTF-8 \
			DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 \
			"$BOT_INSTALL_DIR/TS3AudioBot" \
			--config "$BOT_ROOT/ts3audiobot.toml" \
			--non-interactive \
			--stats-disabled &
		BOT_CHILD_PID=$!
		last_start_ts="$(date +%s)"

		wait "$BOT_CHILD_PID"
		exit_code=$?
		BOT_CHILD_PID=""

		if [ "$SHUTDOWN_REQUESTED" -eq 1 ]; then
			mm_info "Shutdown complete (exit code $exit_code)."
			return "$exit_code"
		fi
		if [ "$exit_code" -eq 0 ]; then
			mm_info "Bot exited cleanly."
			return 0
		fi

		crash_restarts=$((crash_restarts + 1))
		if [ "$crash_restarts" -gt 5 ]; then
			mm_die "Bot exited unexpectedly $crash_restarts times in a row (last exit code: $exit_code). Giving up; the platform restart policy will take over."
		fi
		backoff=$((crash_restarts * 10))
		mm_warn "Bot exited unexpectedly (exit code $exit_code). Restarting in ${backoff}s (restart $crash_restarts/5)..."
		sleep "$backoff"
		if [ "$SHUTDOWN_REQUESTED" -eq 1 ]; then
			return 0
		fi
	done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
	# Allow `docker run <image> scripts/test-connection.sh` style usage:
	# any command other than the default "run" replaces the entrypoint.
	if [ "$#" -gt 0 ] && [ "$1" != "run" ]; then
		exec "$@"
	fi

	mm_info "Mahyar Music starting..."
	if [ "$(id -u)" != "0" ]; then
		mm_die "The entrypoint must run as root (it prepares /data and drops privileges to '$APP_USER')."
	fi

	mm_prepare_storage
	mm_fix_permissions

	mm_check_requirements
	if [ -n "${MM_MISSING:-}" ]; then
		if [ "$MAHYAR_BOOTSTRAP" = "1" ]; then
			mm_bootstrap_wait
		else
			mm_die "Invalid configuration: $MM_MISSING Set MAHYAR_BOOTSTRAP=1 for the first Railway boot if you still need to upload the identity file (docs/RAILWAY_DEPLOYMENT.md)."
		fi
	fi

	mm_info "Configuration validated (secrets are not printed)."
	mm_generate_configs
	mm_generate_test_tone
	mm_fix_permissions

	mm_info "Handing over to the bot process (user '$APP_USER')..."
	mm_run_bot
}

# Run only when executed directly (allows sourcing for local tests).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
