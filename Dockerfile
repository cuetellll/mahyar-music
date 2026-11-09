# =============================================================================
# Mahyar Music – Phase 1 (TeamSpeak 3 voice bot for Railway)
# -----------------------------------------------------------------------------
# Base:   Debian 12 (bookworm) slim
# Engine: TS3AudioBot 0.12.0 – official self-contained linux-x64 release build
#         (the .NET runtime is bundled; no .NET installation is required)
# Needs:  ffmpeg (transcoding) + libopus (voice codec) + libicu (.NET
#         globalization)
#
# The release tarball is pinned by version AND sha256 below. Verified on
# 2026-11-09 against https://github.com/Splamy/TS3AudioBot/releases/tag/0.12.0
# =============================================================================

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# Pinned upstream release (version + sha256 of TS3AudioBot_linux_x64.tar.gz)
ARG TS3AB_VERSION=0.12.0
ARG TS3AB_SHA256=f20fa154eb6401f125877a578bfba9be6543acb0600d0a8d711c5d5ac77f4e71

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		ffmpeg \
		gosu \
		libicu72 \
		libopus0 \
	&& rm -rf /var/lib/apt/lists/*

# Download the pinned release, verify its checksum, extract.
# Tarball contents: the self-contained "TS3AudioBot" binary + WebInterface/.
RUN curl -fsSL -o /tmp/ts3ab.tar.gz \
		"https://github.com/Splamy/TS3AudioBot/releases/download/${TS3AB_VERSION}/TS3AudioBot_linux_x64.tar.gz" \
	&& echo "${TS3AB_SHA256}  /tmp/ts3ab.tar.gz" | sha256sum -c - \
	&& mkdir -p /opt/ts3audiobot \
	&& tar -xzf /tmp/ts3ab.tar.gz -C /opt/ts3audiobot \
	&& rm -f /tmp/ts3ab.tar.gz \
	&& chmod 0755 /opt/ts3audiobot/TS3AudioBot

# Dedicated unprivileged user for the bot process.
# The entrypoint starts as root only to prepare /data, then drops privileges.
RUN useradd --uid 10001 --user-group --create-home --home-dir /var/lib/ts3ab \
	--shell /usr/sbin/nologin ts3ab

COPY docker/entrypoint.sh /app/entrypoint.sh
COPY docker/nlog.config.template /app/nlog.config.template
COPY scripts/ /app/scripts/
RUN chmod 0755 /app/entrypoint.sh /app/scripts/*.sh

# Default working directory for the bot (runtime state lives on the volume).
RUN mkdir -p /data/bot /data/secrets
WORKDIR /data/bot

# The entrypoint prepares /data, generates the configuration from environment
# variables and finally runs TS3AudioBot as user 'ts3ab'.
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
