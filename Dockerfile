# =============================================================================
#  Black Ops 3 dedicated server (t7x / EZZBOIII) running under Wine
#  Base: Debian bookworm + WineHQ staging + SteamCMD
# =============================================================================
FROM debian:bookworm-slim

# --- Build-time behaviour ----------------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive

# --- Runtime environment -----------------------------------------------------
# BO3 is 64-bit -> WINEARCH=win64. The Wine prefix lives on a persisted volume
# so the generated prefix survives container rebuilds.
ENV USER_NAME=bo3 \
    USER_UID=1000 \
    HOME=/home/bo3 \
    WINEARCH=win64 \
    WINEPREFIX=/data/wineprefix \
    WINEDEBUG=-all \
    STEAMCMD_DIR=/opt/steamcmd \
    SERVER_DIR=/data/serverfiles \
    CONFIG_DIR=/config

# --- Base packages -----------------------------------------------------------
# The i386 architecture is required by Wine (32-bit) and SteamCMD.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
        unzip \
        xz-utils \
        cabextract \
        winbind \
        xvfb \
        procps \
        tzdata \
        lib32gcc-s1 \
        python3 \
        gettext-base \
 && rm -rf /var/lib/apt/lists/*

# --- WineHQ staging (Debian bookworm branch) ---------------------------------
RUN mkdir -pm755 /etc/apt/keyrings \
 && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
 && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
 && apt-get update \
 && apt-get install -y --install-recommends winehq-staging \
 && rm -rf /var/lib/apt/lists/*

# --- SteamCMD (standalone tarball, avoids the interactive EULA prompt) --------
RUN mkdir -p "${STEAMCMD_DIR}" \
 && curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
    | tar -xz -C "${STEAMCMD_DIR}"

# --- Non-root user (Wine refuses to run as root) -----------------------------
RUN useradd --uid "${USER_UID}" --create-home --home-dir "${HOME}" --shell /bin/bash "${USER_NAME}" \
 && mkdir -p /data "${SERVER_DIR}" "${WINEPREFIX}" "${CONFIG_DIR}" \
 && chown -R "${USER_NAME}:${USER_NAME}" /data "${HOME}" "${STEAMCMD_DIR}" "${CONFIG_DIR}"

# --- Scripts -----------------------------------------------------------------
COPY --chown=bo3:bo3 scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
# RCON terminal: `docker compose exec bo3 rcon`
COPY --chown=bo3:bo3 scripts/rcon.py /usr/local/bin/rcon
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/rcon

USER bo3
WORKDIR /data

# Default game port (UDP). Override with GAME_PORT in .env.
EXPOSE 27017/udp
EXPOSE 27017/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
