#!/usr/bin/env bash
# =============================================================================
#  BO3 dedicated server entrypoint
#
#  Modes:
#    run       -> (default) prepare the Wine prefix and start the server
#    download  -> download the server files through SteamCMD
#    update    -> re-download / validate the server files
#    bash      -> debug shell inside the container
# =============================================================================
set -euo pipefail

# --- Defaults (overridden by the environment / .env) -------------------------
: "${SERVER_DIR:=/data/serverfiles}"
: "${WINEPREFIX:=/data/wineprefix}"
: "${CONFIG_DIR:=/config}"
: "${STEAMCMD_DIR:=/opt/steamcmd}"
: "${GAME_PORT:=27017}"
: "${SERVER_CFG:=server.cfg}"
: "${MOD_ID:=}"
: "${USE_XVFB:=0}"
# Read-only mount of a full BO3 zone/ folder (from a real game install). Its
# .ff/.fd map files are symlinked into the server zone to unlock every map,
# without copying (the huge .xpak assets are not needed for a headless server).
: "${FULLGAME_ZONE_DIR:=/fullgame_zone}"

# STEAM_USER defaults to "anonymous": app 545990 (the BO3 dedicated server) is
# downloadable anonymously, with no account and no game ownership. Only set a
# real account if the anonymous download ever stops working.
: "${STEAM_USER:=anonymous}"

# Custom client to run: "boiii" (EZZBOIII) or "t7x".
: "${CLIENT:=t7x}"

# Values injected into the .cfg templates at startup. Keeping them here rather
# than in the config files means no secret is ever committed to the repository.
: "${SERVER_NAME:=BO3 Dedicated Server}"
: "${SERVER_DESCRIPTION:=Private match}"
: "${SERVER_PASSWORD:=}"
: "${RCON_PASSWORD:=}"
: "${MAX_PLAYERS:=12}"
export SERVER_NAME SERVER_DESCRIPTION SERVER_PASSWORD RCON_PASSWORD MAX_PLAYERS

# App 545990 installs the server into an UnrankedServer/ subfolder. That is
# where the server executable, the zone/ folder and the fast files live, so it
# is also where the client runs from and where the configs are written.
RUN_DIR="$SERVER_DIR/UnrankedServer"

APP_ID=545990
BOIII_EXE_URL="https://github.com/Ezz-lol/boiii-free/releases/latest/download/boiii.exe"
T7X_EXE_URL="https://master.bo3.eu/t7x/t7x.exe"
DEDICATED_EXE="BlackOps3_UnrankedDedicatedServer.exe"

log() { echo "[entrypoint] $*"; }

# --- Server files download (SteamCMD) ----------------------------------------
download_serverfiles() {
    log "Downloading BO3 server files (app $APP_ID) through SteamCMD."
    if [ "$STEAM_USER" = "anonymous" ]; then
        log ">>> Anonymous Steam login (no account required, non-interactive)."
    else
        log ">>> Steam login as '$STEAM_USER': password and Steam Guard code may"
        log ">>> be prompted (run: docker compose run --rm bo3 download)."
    fi
    mkdir -p "$SERVER_DIR"
    # IMPORTANT: @sSteamCmdForcePlatformType windows must come BEFORE +login.
    # App 545990 only ships a Windows depot; if the platform is still Linux at
    # login time, SteamCMD fails with "Missing configuration".
    "$STEAMCMD_DIR/steamcmd.sh" \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir "$SERVER_DIR" \
        +login "$STEAM_USER" \
        +app_update "$APP_ID" validate \
        +quit
    log "Server files downloaded into $SERVER_DIR."
}

# --- Custom client download --------------------------------------------------
fetch_client_exe() {
    mkdir -p "$RUN_DIR"
    local url
    case "$CLIENT" in
        boiii) url="$BOIII_EXE_URL" ;;
        t7x)   url="$T7X_EXE_URL" ;;
        *)     log "ERROR: unknown CLIENT='$CLIENT' (expected: boiii or t7x)."; exit 1 ;;
    esac
    if [ ! -f "$RUN_DIR/$CLIENT.exe" ]; then
        log "Downloading $CLIENT.exe..."
        curl -fL "$url" -o "$RUN_DIR/$CLIENT.exe"
    fi
}

# --- Wine prefix setup -------------------------------------------------------
setup_wineprefix() {
    if [ ! -d "$WINEPREFIX/drive_c" ]; then
        log "Initialising the Wine prefix ($WINEPREFIX)..."
        WINEDLLOVERRIDES="mscoree=d;mshtml=d" wineboot --init
        wineserver -w || true
    fi

    # EZZBOIII expects its data folder under the prefix's AppData/Local.
    if [ "$CLIENT" = "boiii" ]; then
        local localappdata="$WINEPREFIX/drive_c/users/$(whoami)/AppData/Local"
        if [ ! -d "$localappdata/boiii" ]; then
            log "Extracting boiii-server-files.zip into AppData/Local/boiii ..."
            local tmp
            tmp="$(mktemp -d)"
            curl -fL "https://github.com/framilano/BlackOps3ServerInstaller/raw/main/boiii-server-files.zip" \
                -o "$tmp/boiii-server-files.zip"
            unzip -q "$tmp/boiii-server-files.zip" -d "$tmp"
            mkdir -p "$localappdata"
            cp -r "$tmp/boiii" "$localappdata/"
            rm -rf "$tmp"
            log "boiii folder placed in $localappdata/boiii"
        fi
    fi
}

# --- Config rendering --------------------------------------------------------
# The .cfg files in /config are templates: ${SERVER_NAME}, ${RCON_PASSWORD}...
# are replaced with the values coming from .env before the server reads them.
render_configs() {
    if [ -z "$RCON_PASSWORD" ]; then
        log "WARNING: RCON_PASSWORD is empty; remote administration is disabled."
    fi
    mkdir -p "$RUN_DIR/zone"
    local f dest
    for f in server.cfg server_zm.cfg server_cp.cfg; do
        [ -f "$CONFIG_DIR/$f" ] || continue
        dest="$RUN_DIR/zone/$f"
        # Remove any existing file/symlink first: an old symlink here would
        # point back at the source template, and `>` would truncate it (i.e.
        # destroy the source) before envsubst could read it.
        rm -f "$dest"
        envsubst '${SERVER_NAME} ${SERVER_DESCRIPTION} ${SERVER_PASSWORD} ${RCON_PASSWORD} ${MAX_PLAYERS}' \
            < "$CONFIG_DIR/$f" > "$dest"
    done
}

# --- Merge extra maps from a full game zone (symlinks, no copy) --------------
merge_maps() {
    if [ ! -d "$FULLGAME_ZONE_DIR" ]; then
        return 0
    fi
    local f base added=0
    for f in "$FULLGAME_ZONE_DIR"/*.ff "$FULLGAME_ZONE_DIR"/*.fd; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        # Only add maps that are missing; never override the dedicated files.
        if [ ! -e "$RUN_DIR/zone/$base" ]; then
            ln -s "$f" "$RUN_DIR/zone/$base" && added=$((added + 1))
        fi
    done
    if [ "$added" -gt 0 ]; then
        log "Merged $added extra map file(s) from the full game zone."
    else
        log "Full game zone mounted, no new map files to add."
    fi
}

# --- Stage GSC scripts for the active mode only (no cross-mode crashes) ------
# Zombies-only scripts #include zm-only engine modules, resolved at load time
# (not conditionally). Leaving them in custom_scripts/ while running mp/cp
# aborts the whole script load -> the game process exits -> restart loop.
# So only the active mode's scripts (plus all/) ever get copied in.
stage_custom_scripts() {
    local dest="$RUN_DIR/t7x/custom_scripts"
    local lib="$RUN_DIR/t7x/scripts_library"
    local mode
    case "$SERVER_CFG" in
        *_zm.cfg) mode=zm ;;
        *_cp.cfg) mode=cp ;;
        *)        mode=mp ;;
    esac

    mkdir -p "$dest"
    rm -f "$dest"/*.gsc 2>/dev/null || true

    local src d count=0
    for d in all "$mode"; do
        src="$lib/$d"
        [ -d "$src" ] || continue
        for f in "$src"/*.gsc; do
            [ -e "$f" ] || continue
            cp "$f" "$dest/" && count=$((count + 1))
        done
    done
    log "Staged $count custom script(s) for mode '$mode'."
}

# --- Server startup ----------------------------------------------------------
run_server() {
    if [ ! -f "$RUN_DIR/$DEDICATED_EXE" ]; then
        if [ "$STEAM_USER" = "anonymous" ]; then
            log "Server files missing -> downloading automatically (anonymous)."
            download_serverfiles
        else
            log "ERROR: server files missing ($DEDICATED_EXE not found)."
            log "Non-anonymous account -> run: docker compose run --rm bo3 download"
            exit 1
        fi
    fi

    fetch_client_exe
    setup_wineprefix
    render_configs
    merge_maps
    stage_custom_scripts

    # Wine complains when XDG_RUNTIME_DIR is unset (warning, sometimes fatal).
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-bo3}"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    cd "$RUN_DIR"
    log "Starting server | client=$CLIENT | port=$GAME_PORT | cfg=$SERVER_CFG | mod='${MOD_ID:-none}'"

    if [ "$USE_XVFB" = "1" ]; then
        log "USE_XVFB=1 -> starting a virtual display."
        Xvfb :0 -screen 0 640x480x8 -nolisten tcp &
        export DISPLAY=:0
    fi

    # The client writes nothing to stdout (it draws an ANSI console into a TTY).
    # Streaming its console log file is what makes `docker logs -f` readable.
    local console_log="$RUN_DIR/identities/dedicatedpc/console_mp.log"
    mkdir -p "$(dirname "$console_log")"
    : > "$console_log"
    tail -n +1 -F "$console_log" 2>/dev/null &
    local tail_pid=$!

    wine "$CLIENT.exe" -dedicated \
        +set fs_game "$MOD_ID" \
        +set net_port "$GAME_PORT" \
        +set logfile 2 \
        +exec "$SERVER_CFG" &
    local game_pid=$!

    # Graceful shutdown: forward `docker stop` to the game process.
    trap 'kill -TERM "$game_pid" 2>/dev/null || true' TERM INT

    local rc=0
    wait "$game_pid" || rc=$?
    kill "$tail_pid" 2>/dev/null || true
    log "Server stopped (exit code $rc)."
    exit "$rc"
}

# --- Dispatch ----------------------------------------------------------------
cmd="${1:-run}"
case "$cmd" in
    download) download_serverfiles ;;
    update)   download_serverfiles ;;
    run)      run_server ;;
    bash|sh)  exec /bin/bash ;;
    *)        exec "$@" ;;
esac
