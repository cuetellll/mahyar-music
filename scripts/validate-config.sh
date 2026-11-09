#!/usr/bin/env bash
# =============================================================================
# Mahyar Music – configuration & identity validation
# -----------------------------------------------------------------------------
# Shared function library, sourced by docker/entrypoint.sh. It can also be run
# standalone inside the container:
#
#   bash /app/scripts/validate-config.sh
#
# SECURITY: this script parses the TeamSpeak identity file but NEVER prints
# its contents. Only the security-level prefix (a non-secret number) and the
# value length are reported.
# =============================================================================

mm_identity_read() {
	# Reads the TeamSpeak identity from $1 and exports:
	#   MM_IDENTITY_KEY   – the identity string (kept in memory only)
	#   MM_IDENTITY_LEVEL – the security-level prefix (safe to display)
	# Returns non-zero if the format is not recognized.
	local file="$1"
	local value=""

	if [ ! -f "$file" ]; then
		mm_die "Identity file not found: $file (see docs/SECURITY.md for the import procedure)."
	fi
	if [ ! -r "$file" ]; then
		mm_die "Identity file is not readable: $file"
	fi

	# Preferred source: an identity exported by the TeamSpeak 3 client
	# (Tools -> Identities -> Export), i.e. an ini containing 'identity=...'.
	value="$(sed -n 's/^[[:space:]]*identity[[:space:]]*=[[:space:]]*//p' "$file" | tail -n 1)"

	# Fallback: a raw single-line identity file.
	if [ -z "$value" ]; then
		value="$(grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' | head -n 1)"
	fi

	# Strip a trailing CR first (Windows exports), then optional surrounding
	# quotes, then the '~' suffix TeamSpeak client strings may carry (the
	# bot's parser, TsCrypt.IdentityRegex in TS3AudioBot 0.12.0, only accepts
	# '<level>V<base64>').
	value="${value%$'\r'}"
	value="${value%\"}"
	value="${value#\"}"
	value="${value%\'}"
	value="${value#\'}"
	value="${value%%~*}"

	# Same shape as TsCrypt.IdentityRegex: ^(level)V(base64)$
	if [[ ! "$value" =~ ^[0-9]+V[A-Za-z0-9+/]+={0,2}$ ]]; then
		echo "[ERROR] [Mahyar Music] The identity value in $file has an unrecognized format." >&2
		echo "[ERROR] [Mahyar Music] Expected a TeamSpeak3 client identity ('<level>V<base64>')," >&2
		echo "[ERROR] [Mahyar Music] e.g. an ini exported by the TS3 client containing an 'identity=' line." >&2
		return 1
	fi

	MM_IDENTITY_KEY="$value"
	MM_IDENTITY_LEVEL="${value%%V*}"
	mm_info "Identity loaded from $file (format: TeamSpeak3 client identity, security level prefix: $MM_IDENTITY_LEVEL, length: ${#MM_IDENTITY_KEY})."
	return 0
}

mm_identity_perms_warn() {
	# Warns when the identity file is readable by group/other (POSIX only).
	local file="$1"
	local perms
	perms="$(stat -c '%a' "$file" 2>/dev/null)" || return 0
	case "$perms" in
		600|400)
			: # restrictive enough
			;;
		*)
			mm_warn "Identity file permissions are '$perms' (expected 600); they will be tightened automatically."
			;;
	esac
}

# Standalone check mode (does not start the bot).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	mm_info() { echo "[INFO]  [Mahyar Music] $*"; }
	mm_warn() { echo "[WARN]  [Mahyar Music] $*" >&2; }
	mm_die()  { echo "[ERROR] [Mahyar Music] $*" >&2; exit 1; }

	DATA_DIR="${DATA_DIR:-/data}"
	TS3_IDENTITY_FILE="${TS3_IDENTITY_FILE:-$DATA_DIR/secrets/identity.ini}"
	TS3_HOST="${TS3_HOST:-}"
	TS3_VOICE_PORT="${TS3_VOICE_PORT:-9987}"
	TS3_CHANNEL_ID="${TS3_CHANNEL_ID:-}"
	TS3_CHANNEL_PATH="${TS3_CHANNEL_PATH:-}"

	status=0

	if [ -z "$TS3_HOST" ]; then
		mm_die "TS3_HOST is not set."
	fi
	if ! [[ "$TS3_VOICE_PORT" =~ ^[0-9]+$ ]] || [ "$TS3_VOICE_PORT" -lt 1 ] || [ "$TS3_VOICE_PORT" -gt 65535 ]; then
		mm_die "TS3_VOICE_PORT must be an integer between 1 and 65535."
	fi
	mm_info "Connection target: $TS3_HOST:$TS3_VOICE_PORT"

	if [ -n "$TS3_CHANNEL_ID" ]; then
		[[ "$TS3_CHANNEL_ID" =~ ^[0-9]+$ ]] || { mm_die "TS3_CHANNEL_ID must be numeric."; }
		mm_info "Target channel id: /$TS3_CHANNEL_ID"
	elif [ -n "$TS3_CHANNEL_PATH" ]; then
		mm_info "Target channel path: $TS3_CHANNEL_PATH"
	else
		mm_die "Either TS3_CHANNEL_ID or TS3_CHANNEL_PATH must be set."
	fi

	if mm_identity_read "$TS3_IDENTITY_FILE"; then
		mm_identity_perms_warn "$TS3_IDENTITY_FILE"
	else
		status=1
	fi

	if [ "$status" -eq 0 ]; then
		mm_info "Configuration validation PASSED (no secrets were printed)."
	else
		mm_die "Configuration validation FAILED."
	fi
	exit "$status"
fi
