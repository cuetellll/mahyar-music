# =============================================================================
# Mahyar Music – Phase 1 (TeamSpeak 3 voice bot for Railway)
# -----------------------------------------------------------------------------
# Base:   Debian 12 (bookworm) slim
# Engine: TS3AudioBot 0.12.0 – official self-contained linux-x64 release build
#         (the .NET runtime is bundled; no .NET installation is required)
# Needs:  ffmpeg (transcoding) + libopus (voice codec) + libssl1.1 (.NET TLS)
#
# NOTE 1: no libicu on purpose — the pinned .NET Core 3.1 runtime inside the
# 0.12.0 build only knows ICU <= 67 and would FailFast on Debian 12's ICU 72.
# The entrypoint sets DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 instead (safe
# for this bot; no locale formatting is used).
# NOTE 2: the same runtime requires OpenSSL 1.1 (libssl.so.1.1) and crashes at
# startup with "No usable version of libssl was found" on Debian 12 (which
# ships only OpenSSL 3). The last bullseye libssl1.1 package is installed
# below, pinned by sha256 from the official Debian archive.
# NOTE 3: the bot's native loader probes an UNVERSIONED "libopus.so"
# (upstream's InstallOpus.sh copies .libs/libopus.so to /usr/lib). Debian's
# libopus0 only ships libopus.so.0; libopus-dev provides the libopus.so link
# the DllImport probe order ("libopus" -> "libopus.so" -> "liblibopus.so")
# resolves.
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
		libopus-dev \
	&& rm -rf /var/lib/apt/lists/*

# OpenSSL 1.1 for the .NET Core 3.1 runtime (see NOTE 2 above).
# Pinned: libssl1.1_1.1.1w-0+deb11u1_amd64.deb from archive.debian.org,
# verified 2026-11-09. License notices land in
# /usr/share/doc/libssl1.1/copyright.
ARG LIBSSL11_VERSION=1.1.1w-0+deb11u1
ARG LIBSSL11_SHA256=aadf8b4b197335645b230c2839b4517aa444fd2e8f434e5438c48a18857988f7
RUN curl -fsSL -o /tmp/libssl1.1.deb \
		"https://archive.debian.org/debian/pool/main/o/openssl/libssl1.1_${LIBSSL11_VERSION}_amd64.deb" \
	&& echo "${LIBSSL11_SHA256}  /tmp/libssl1.1.deb" | sha256sum -c - \
	&& dpkg -i /tmp/libssl1.1.deb \
	&& rm -f /tmp/libssl1.1.deb \
	&& ldconfig

# Download the pinned release, verify its checksum, extract.
# Tarball contents: the self-contained "TS3AudioBot" binary + WebInterface/.
RUN curl -fsSL -o /tmp/ts3ab.tar.gz \
		"https://github.com/Splamy/TS3AudioBot/releases/download/${TS3AB_VERSION}/TS3AudioBot_linux_x64.tar.gz" \
	&& echo "${TS3AB_SHA256}  /tmp/ts3ab.tar.gz" | sha256sum -c - \
	&& mkdir -p /opt/ts3audiobot \
	&& tar -xzf /tmp/ts3ab.tar.gz -C /opt/ts3audiobot \
	&& rm -f /tmp/ts3ab.tar.gz \
	&& chmod 0755 /opt/ts3audiobot/TS3AudioBot \
	&& ln -sf /usr/lib/x86_64-linux-gnu/libopus.so.0 /opt/ts3audiobot/libopus.so

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
