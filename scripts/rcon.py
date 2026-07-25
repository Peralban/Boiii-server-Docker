#!/usr/bin/env python3
"""
RCON CLI for the BO3 server (classic Call of Duty UDP RCON protocol).

Usage:
    rcon                    -> interactive terminal (history, tab-complete)
    rcon status             -> run a single raw command and print the reply
    rcon players            -> parsed, clean player table
    rcon kick <num|name>    -> kick a player from the last-seen player list
    rcon watch <cmd...>     -> re-run a command every 2s until Ctrl-C
    rcon reset              -> reset all zm_tweaks dvars to a normal game
    rcon switch <preset>    -> request a mode/preset switch (see below)

Requesting `switch <preset>` writes the preset name to a file the host-side
start script watches for; it then restarts the server with that preset and
re-opens this CLI. Requires running through start.ps1/start.sh, not a plain
`docker compose exec bo3 rcon`.

The password is resolved in this order:
  1. the RCON_PASSWORD environment variable
  2. the `set rcon_password "..."` line of the rendered server config
"""
import os

# Without TERM set, readline can't look up escape sequences for arrow keys
# (up/down history, left/right cursor movement) and prints them raw instead
# of acting on them. `docker exec` sessions don't always inherit TERM from
# the host shell, so default it before readline is used.
os.environ.setdefault("TERM", "xterm")

import re
import readline
import socket
import sys
import time

HOST = os.environ.get("RCON_HOST", "127.0.0.1")
PORT = int(os.environ.get("GAME_PORT", "27017"))
TIMEOUT = float(os.environ.get("RCON_TIMEOUT", "1.5"))
HISTORY_FILE = os.environ.get("RCON_HISTORY_FILE", "/data/.rcon_history")
CONFIG_DIR = os.environ.get("CONFIG_DIR", "/config")
SWITCH_REQUEST_FILE = os.path.join(CONFIG_DIR, ".switch_request")

PREFIX = b"\xff\xff\xff\xff"
USE_COLOR = sys.stdout.isatty()

KNOWN_COMMANDS = [
    "status", "serverinfo", "players", "kick", "watch", "help", "exit", "reset",
    "switch", "map", "map_rotate", "fast_restart", "say", "tell",
    "banclient", "tempbanclient", "unbanuser", "clientkick",
    "g_gametype", "set", "rcon_password", "sv_hostname",
]

# Dvars commonly changed at runtime, offered for tab-completion after `set `.
KNOWN_DVARS = [
    "bot_maxallies", "bot_maxAxis", "bot_maxFree", "bot_difficulty",
    "sv_hostname", "g_password", "rcon_password", "g_gametype",
    "sv_maxclients", "scr_teambalance", "cg_thirdPerson",
    "zm_money_multiplier", "zm_starting_money", "zm_no_perk_limit",
    "zm_perk_drop_chance", "zm_godmode", "zm_infinite_ammo",
]

# Presets offered for tab-completion after `switch `. Keep in sync with the
# config/server_<name>.cfg files switch.sh/switch.ps1 know about.
KNOWN_PRESETS = ["mp", "zm", "cp", "snipe1v1", "7v7bots"]

# Defaults for the zm_tweaks.gsc dvars (see t7x/scripts_library/zm/) — a
# completely normal game. `rcon reset` restores all of them in one shot.
ZM_TWEAK_DEFAULTS = {
    "zm_money_multiplier": "1",
    "zm_starting_money": "0",
    "zm_no_perk_limit": "0",
    "zm_perk_drop_chance": "0",
    "zm_godmode": "0",
    "zm_infinite_ammo": "0",
}

UNIVERSAL_HELP = """\
RCON CLI for the BO3 server. Usage: `rcon` (interactive) or `rcon <command>`.

Shortcuts:
  players (or ls)          clean player table
  kick <#|name>             kick from the last-seen player list
  watch <command>           re-run a command every 2s until Ctrl-C
  switch <preset>           mp | zm | cp | snipe1v1 | 7v7bots — restarts the
                            server with that preset, reopens this CLI
                            (only works when launched via start.ps1/start.sh)
  help                      this message (adapts to the active mode)

Any other input is sent as a raw RCON command, e.g.:
  status | serverinfo | map <name> | map_rotate | fast_restart
  say <message> | tell <#> <message>
  banclient <#> | tempbanclient <#> | unbanuser <name>\
"""

MP_HELP = """

-- Multiplayer (active mode) --
  reset                             n/a in mp (zombies-only tweaks)
  set bot_maxallies <n>             bots on the Allies team
  set bot_maxAxis <n>               bots on the Axis team
  set bot_maxFree <n>               bots in free-for-all modes (dm)
  set bot_difficulty <n>            0=easy 1=normal 2=hard 3=veteran
  g_gametype <mode>                 tdm, dom, dm, sd, conf, ctf, koth, gun...
  (bot/gametype changes need map_rotate or map <name> to apply)
  Run `help maps` for the full map codename list.\
"""

ZM_HELP = """

-- Zombies (active mode) -- zm_tweaks.gsc dvars, all reset by `reset`:
  set zm_money_multiplier <n>       points scalar (1 = normal, decimals OK)
  set zm_starting_money <n>         bonus points on spawn
  set zm_no_perk_limit 1            allow up to 9 perks
  set zm_perk_drop_chance <pct>     % chance a kill drops a free perk
  set zm_godmode 1                  invulnerable players
  set zm_infinite_ammo 1            never run out of ammo
  reset                             back to a normal game, one command
  Run `help maps` for the full map codename list.\
"""

CP_HELP = """

-- Campaign co-op (active mode) --
  Up to 4 players. `reset` is not applicable (zombies-only tweaks).\
"""


# Codename -> real name, cross-checked against the actual .ff files present
# on the server (config/server.cfg keeps the DLC grouping in comments).
MP_MAPS = [
    ("mp_biodome", "Aquarium"), ("mp_spire", "Breach"), ("mp_sector", "Combine"),
    ("mp_apartments", "Evac"), ("mp_chinatown", "Exodus"), ("mp_veiled", "Fringe"),
    ("mp_havoc", "Havoc"), ("mp_ethiopia", "Hunted"), ("mp_infection", "Infection"),
    ("mp_metro", "Metro"), ("mp_redwood", "Redwood"), ("mp_stronghold", "Stronghold"),
    ("mp_nuketown_x", "Nuk3town"),
    ("mp_crucible", "Gauntlet (Awakening)"), ("mp_rise", "Rise (Awakening)"),
    ("mp_skyjacked", "Skyjacked (Awakening)"), ("mp_waterpark", "Splash (Awakening)"),
    ("mp_kung_fu", "Knockout (Eclipse)"), ("mp_conduit", "Rift (Eclipse)"),
    ("mp_aerospace", "Spire (Eclipse)"), ("mp_banzai", "Verge (Eclipse)"),
    ("mp_shrine", "Berserk (Descent)"), ("mp_cryogen", "Cryogen (Descent)"),
    ("mp_rome", "Empire (Descent)"), ("mp_arena", "Rumble (Descent)"),
    ("mp_ruins", "Citadel (Salvation)"), ("mp_miniature", "Micro (Salvation)"),
    ("mp_western", "Outlaw (Salvation)"), ("mp_city", "Rupture (Salvation)"),
    ("mp_veiled_heyday", "Fringe Night (Bonus)"), ("mp_redwood_ice", "Redwood Snow (Bonus)"),
    ("mp_freerun_01", "Freerun 1"), ("mp_freerun_02", "Freerun 2"),
    ("mp_freerun_03", "Freerun 3"), ("mp_freerun_04", "Freerun 4"),
]

ZM_MAPS = [
    ("zm_zod", "Shadows of Evil"), ("zm_factory", "The Giant"),
    ("zm_castle", "Der Eisendrache"), ("zm_island", "Zetsubou No Shima"),
    ("zm_stalingrad", "Gorod Krovi"), ("zm_genesis", "Revelations"),
    ("zm_tomb", "Origins (Zombies Chronicles)"),
    ("zm_prototype", "Nacht der Untoten (ZC)"), ("zm_asylum", "Verruckt (ZC)"),
    ("zm_sumpf", "Shi No Numa (ZC)"), ("zm_theater", "Kino der Toten (ZC)"),
    ("zm_cosmodrome", "Ascension (ZC)"), ("zm_temple", "Shangri-La (ZC)"),
    ("zm_moon", "Moon (ZC)"),
]


def print_maps():
    mode = get_mode()
    if mode == "mp":
        title, maps = "Multiplayer maps", MP_MAPS
    elif mode == "zm":
        title, maps = "Zombies maps", ZM_MAPS
    else:
        print(color("No map codename list for campaign co-op.", "33"))
        return
    print(color(f"-- {title} ({len(maps)}) --", "36"))
    for code, name in maps:
        print(f"  {code:<18} {name}")


def get_mode():
    """Derive the active mode from SERVER_CFG, same convention as entrypoint.sh."""
    cfg = os.environ.get("SERVER_CFG", "server.cfg")
    if cfg.endswith("_zm.cfg"):
        return "zm"
    if cfg.endswith("_cp.cfg"):
        return "cp"
    return "mp"


def build_help():
    mode = get_mode()
    extra = {"mp": MP_HELP, "zm": ZM_HELP, "cp": CP_HELP}.get(mode, "")
    return UNIVERSAL_HELP + extra


def color(text, code):
    return f"\033[{code}m{text}\033[0m" if USE_COLOR else text


def strip_colors(text):
    """Remove CoD color codes (^1, ^2, ...) so output is readable in a terminal."""
    return re.sub(r"\^[0-9]", "", text)


def read_password():
    """Resolve the RCON password from the environment or the rendered config."""
    env = os.environ.get("RCON_PASSWORD")
    if env:
        return env

    # Fall back to the rendered config (the one in /config is a template and
    # still holds the ${RCON_PASSWORD} placeholder).
    server_dir = os.environ.get("SERVER_DIR", "/data/serverfiles")
    cfg_name = os.environ.get("SERVER_CFG", "server.cfg")
    path = os.path.join(server_dir, "UnrankedServer", "zone", cfg_name)
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            match = re.search(
                r'^\s*set\s+rcon_password\s+"([^"]*)"', fh.read(), re.MULTILINE
            )
            if match:
                return match.group(1)
    except OSError:
        pass
    return ""


def send_command(sock, password, command):
    """Send one RCON command and collect the reply packets."""
    payload = PREFIX + b"rcon " + password.encode() + b" " + command.encode()
    sock.sendto(payload, (HOST, PORT))

    parts = []
    while True:
        try:
            data, _ = sock.recvfrom(65535)
        except socket.timeout:
            break
        if data.startswith(PREFIX):
            data = data[len(PREFIX):]
        if data.startswith(b"print\n"):
            data = data[len(b"print\n"):]
        parts.append(data.decode("utf-8", "replace"))
    return strip_colors("".join(parts).strip())


def parse_players(status_reply):
    """Extract player rows from a `status` reply: (num, score, ping, name, address)."""
    players = []
    for line in status_reply.splitlines():
        m = re.match(
            r"\s*(\d+)\s+(-?\d+)\s+(\d+)\s+(\S*)\s+(.{1,32}?)\s+"
            r"([\d.]+:\d+|unknown|bot\d*)\s+(\d+)\s*$",
            line,
        )
        if m:
            num, score, ping, _xuid, name, addr, _qport = m.groups()
            players.append({
                "num": num, "score": score, "ping": ping,
                "name": name.strip(), "addr": addr,
            })
    return players


def print_players(players):
    if not players:
        print(color("No players connected.", "33"))
        return
    print(f"{'#':<3} {'score':<6} {'ping':<5} {'name':<24} address")
    print("-" * 60)
    for p in players:
        print(f"{p['num']:<3} {p['score']:<6} {p['ping']:<5} {p['name']:<24} {p['addr']}")


def do_players(sock, password):
    reply = send_command(sock, password, "status")
    players = parse_players(reply)
    print_players(players)
    return players


def setup_readline():
    try:
        readline.read_history_file(HISTORY_FILE)
    except OSError:
        pass
    readline.set_history_length(500)

    def completer(text, state):
        buf = readline.get_line_buffer().lower()
        if buf.startswith("set "):
            candidates = KNOWN_DVARS
        elif buf.startswith("switch "):
            candidates = KNOWN_PRESETS
        else:
            candidates = KNOWN_COMMANDS
        matches = [c for c in candidates if c.startswith(text)]
        return matches[state] if state < len(matches) else None

    readline.set_completer(completer)
    readline.parse_and_bind("tab: complete")


def save_history():
    try:
        os.makedirs(os.path.dirname(HISTORY_FILE), exist_ok=True)
        readline.write_history_file(HISTORY_FILE)
    except OSError:
        pass


def print_reply(reply):
    if reply:
        print(reply)
    else:
        print(color("(no reply from server — check the password or that the server is up)", "33"))


def dispatch(sock, password, line, last_players):
    """Handle one command line (used by both interactive and single-shot modes).

    Returns "exit" when the interactive loop should terminate (e.g. after a
    switch request), None otherwise.
    """
    parts = line.split()
    cmd = parts[0].lower() if parts else ""

    if cmd == "players" or cmd == "ls":
        last_players[:] = do_players(sock, password)
        return None

    if cmd == "kick" and len(parts) > 1:
        target = parts[1]
        match = None
        if target.isdigit():
            match = next((p for p in last_players if p["num"] == target), None)
        else:
            match = next((p for p in last_players if target.lower() in p["name"].lower()), None)
        if not match:
            print(color(f"No known player matches '{target}'. Run 'players' first.", "31"))
            return
        print_reply(send_command(sock, password, f"clientkick {match['num']}"))
        return

    if cmd == "watch" and len(parts) > 1:
        sub = " ".join(parts[1:])
        print(color(f"Watching '{sub}' every 2s. Ctrl-C to stop.", "36"))
        try:
            while True:
                if USE_COLOR:
                    print("\033[H\033[J", end="")  # ANSI clear, no TERM/subprocess needed
                print(color(f"-- {sub} (refreshing every 2s) --", "36"))
                if sub.split()[0] in ("players", "ls"):
                    do_players(sock, password)
                else:
                    print_reply(send_command(sock, password, sub))
                time.sleep(2)
        except KeyboardInterrupt:
            print()
        return

    if cmd == "switch" and len(parts) > 1:
        preset = parts[1]
        try:
            os.makedirs(CONFIG_DIR, exist_ok=True)
            with open(SWITCH_REQUEST_FILE, "w", encoding="utf-8") as fh:
                fh.write(preset + "\n")
        except OSError as exc:
            print(color(f"Could not write switch request: {exc}", "31"))
            return None
        print(color(
            f"Switch to '{preset}' requested — exiting so the host can "
            "restart the server and reopen this CLI...", "36"
        ))
        return "exit"

    if cmd == "reset":
        for dvar, default in ZM_TWEAK_DEFAULTS.items():
            send_command(sock, password, f'set {dvar} "{default}"')
        print(color("All zm_tweaks dvars reset to a normal game:", "32"))
        for dvar, default in ZM_TWEAK_DEFAULTS.items():
            print(f"  {dvar} = {default}")
        return

    if cmd == "help":
        if len(parts) > 1 and parts[1] in ("map", "maps"):
            print_maps()
        else:
            print(build_help())
        return

    print_reply(send_command(sock, password, line))


def main():
    password = read_password()
    if not password:
        print("ERROR: no RCON password found.", file=sys.stderr)
        print("Set RCON_PASSWORD in your .env file.", file=sys.stderr)
        return 1

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(TIMEOUT)
    last_players = []

    # Single command / subcommand mode
    if len(sys.argv) > 1:
        dispatch(sock, password, " ".join(sys.argv[1:]), last_players)
        return 0

    # Interactive terminal mode
    setup_readline()
    print(f"RCON CLI -> {HOST}:{PORT}  (mode: {get_mode()})")
    print("Type 'help' for mode-specific commands. Tab-completes, arrow keys for history.")
    print("'exit' or Ctrl-D to quit.\n")

    try:
        while True:
            try:
                line = input(color("rcon> ", "36")).strip()
            except (EOFError, KeyboardInterrupt):
                print()
                break
            if not line:
                continue
            if line == "exit":
                break
            if dispatch(sock, password, line, last_players) == "exit":
                break
    finally:
        save_history()

    return 0


if __name__ == "__main__":
    sys.exit(main())
