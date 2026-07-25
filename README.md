# Black Ops 3 dedicated server in Docker

A headless BO3 dedicated server running under **Wine** inside a container, based on the
logic of [framilano/BlackOps3ServerInstaller](https://github.com/framilano/BlackOps3ServerInstaller).
Supports the **t7x** and **EZZBOIII** custom clients.

## Contents

1. [Requirements](#1-requirements)
2. [Quick start](#2-quick-start)
3. [Running the server](#3-running-the-server)
4. [RCON CLI](#4-rcon-cli)
5. [Configuration and presets](#5-configuration-and-presets)
6. [Zombies tweaks (custom GSC scripts)](#6-zombies-tweaks-custom-gsc-scripts)
7. [Custom client: t7x vs boiii](#7-custom-client-t7x-vs-boiii)
8. [Hiding your IP (playit.gg tunnel)](#8-hiding-your-ip-playitgg-tunnel)
9. [Resources and performance](#9-resources-and-performance)
10. [Notes and troubleshooting](#10-notes-and-troubleshooting)

## 1. Requirements

- Docker (Docker Desktop on Windows, with the WSL2 backend).
- **No Steam account required**: the dedicated server files (app 545990) download
  anonymously.

## 2. Quick start

```bash
cp .env.example .env
```

Edit `.env` and set at least `RCON_PASSWORD`. Then:

```bash
docker compose up -d
```

On the **first** run the entrypoint automatically downloads the server files
(a few GB) into the `serverdata` volume, then starts the server. Later runs reuse
the volume, so nothing is downloaded again.

## 3. Running the server

### One-command start (recommended)

Starts the server, waits until it is ready, and opens the RCON terminal:

```bash
./start.sh
```

| Option | Effect |
|---|---|
| `./start.sh` | Start + open the RCON terminal |
| `./start.sh --logs` | Start + follow the logs |
| `./start.sh --no-rcon` | Start only, return to the shell |

On Windows: `.\start.ps1`, `.\start.ps1 -Logs`, `.\start.ps1 -NoRcon`.

### Monitoring

```bash
docker logs -f bo3-boiii
```
```bash
docker stats bo3-boiii
```
```bash
docker compose restart bo3
```

The container streams the game's own console log to stdout, so `docker logs` shows
real server output without digging through Wine files.

## 4. RCON CLI

Control the running server (change map, kick, broadcast messages...):

```bash
docker compose exec bo3 rcon
```

A real interactive CLI: **command history** (up/down arrows, persisted across
restarts), **tab-completion** (context-aware: dvar names after `set `, preset names
after `switch `), and colored output. On top of any raw RCON command (`status`,
`serverinfo`, `map_rotate`, `map mp_havoc`, `say <message>`, `g_gametype dom`, ...),
it adds:

| Command | Effect |
|---|---|
| `players` (or `ls`) | Clean player table (color codes stripped) |
| `kick <#\|name>` | Kick by number or partial name, from the last `players` list |
| `watch <command>` | Re-run a command every 2s until Ctrl-C (e.g. `watch players`) |
| `reset` | Reset all `zm_tweaks` dvars (see [section 6](#6-zombies-tweaks-custom-gsc-scripts)) to a normal game, in one shot |
| `switch <preset>` | Restart the server with a different mode/preset and reopen the CLI (see below) |
| `help` | **Adaptive**: shows bot commands in multiplayer, `zm_tweaks` dvars in zombies |
| `help maps` (or `help map`) | Full codename to real name table for the active mode's maps |

Or run any single command without entering the interactive shell:

```bash
docker compose exec bo3 rcon players
docker compose exec bo3 rcon watch players
```

> **IW4MAdmin does not officially support BO3 (T7).** Only an experimental,
> partially working plugin exists for BOIII. The RCON CLI above is the
> reliable option.

### Switching mode/preset from inside the CLI

Typing `switch <preset>` (e.g. `switch snipe1v1`) inside the interactive CLI writes
a request that `start.ps1`/`start.sh` picks up once the CLI exits: it restarts the
server with that preset and reopens the CLI automatically. This **only** works when
the server was launched through `start.ps1`/`start.sh` — a plain
`docker compose exec bo3 rcon` has no wrapper watching for the request.

### Raw RCON command reference

Any of these work as-is, either typed in the interactive CLI or as
`docker compose exec bo3 rcon <command>`:

| Category | Command | Effect |
|---|---|---|
| Info | `status` | Connected players (number, ping, name, address) |
| Info | `serverinfo` | All current server settings |
| Info | `dumpuser <name>` | Details about one player |
| Maps | `map <name>` | Load a specific map (same mode only — MP/ZM needs `switch.sh`/`.ps1`) |
| Maps | `map_rotate` | Advance to the next map in the rotation |
| Maps | `fast_restart` | Restart the current round on the same map |
| Maps | `g_gametype <mode>` | Change gametype (applies on next map load) |
| Players | `kick <name>` | Kick a player by name |
| Players | `clientkick <#>` | Kick a player by number (from `status`) |
| Players | `kick all` | Kick everyone |
| Players | `banclient <#>` | Permanently ban |
| Players | `tempbanclient <#>` | Temporary ban |
| Players | `unbanuser <name>` | Remove a ban |
| Chat | `say <message>` | Broadcast to everyone |
| Chat | `tell <#> <message>` | Whisper to one player |
| Live settings | `set sv_hostname "name"` | Rename the server |
| Live settings | `set g_password "pass"` | Set/clear the join password |
| Live settings | `set scr_<mode>_scorelimit <n>` | Score limit (e.g. `scr_tdm_scorelimit`) |
| Live settings | `set scr_<mode>_timelimit <n>` | Round duration in minutes |
| Fun | `set g_speed <n>` | Player movement speed (default `190`) |
| Fun | `set jump_height <n>` | Jump height |

## 5. Configuration and presets

Config files live in `config/` and are **templates**: placeholders such as
`${RCON_PASSWORD}` are replaced at startup with the values from `.env`. This keeps
every secret out of version control.

| Mode | `SERVER_CFG` value |
|---|---|
| Multiplayer (classic) | `server.cfg` |
| Zombies | `server_zm.cfg` |
| Campaign co-op | `server_cp.cfg` |
| 1v1 snipers, Nuketown, FFA, radar always on | `server_snipe1v1.cfg` |
| 7v7 TDM, bots fill empty slots | `server_7v7bots.cfg` |

Change it in `.env`, then run `docker compose up -d` — or use the switch helper,
which does both:

```bash
./switch.sh snipe1v1      # or: mp | zm | cp | 7v7bots
```

Any `config/server_<name>.cfg` file works as a preset this way, including ones
you add yourself — every `.cfg` in `config/` is picked up automatically, no
code change needed.

### Per-preset game rules (weapon restrictions, radar, time limits...)

BO3 auto-reloads `gamesettings_<gametype>.cfg` (e.g. `gamesettings_dm.cfg` for
free-for-all) whenever a match starts — **after** anything a preset's
`server_<name>.cfg` manually execs. So rule tweaks like weapon restrictions or
`forceRadar` have to live in the actual file the engine reloads, not in the
preset's own config, or they get silently overwritten.

To keep presets that share a gametype from leaking settings into each other,
these live in two places, merged fresh at every startup:

- `t7x/gamesettings_base/` — the stock, untouched rules (never edit these to
  customize a preset; every preset without an override gets these as-is).
- `t7x/gamesettings_overrides/<preset-name>/` — files here overlay the base
  ones for that preset only (e.g. `t7x/gamesettings_overrides/snipe1v1/mp/gamesettings_dm.cfg`
  adds the sniper-only restrictions + always-on radar + no time limit + no
  scorestreaks, but only while `SERVER_CFG=server_snipe1v1.cfg` is active — a
  different `dm` preset without its own override would get plain, unrestricted FFA).

`forceRadar` itself: `0` = normal rules, `1` = sweeping waves, `2` = constant
(matches the in-game custom match "Mini-map" option).

## 6. Zombies tweaks (custom GSC scripts)

Toggleable zombies-only gameplay tweaks (money multiplier, starting money, perk
limit, perk drops, godmode, infinite ammo), driven entirely by dvars settable over
RCON and reset in one shot with the `reset` command (see [section 4](#4-rcon-cli)):

```bash
docker compose exec bo3 rcon set zm_money_multiplier 2
docker compose exec bo3 rcon set zm_perk_drop_chance 5
docker compose exec bo3 rcon map_restart
```

- Source: `gsc_source/zm_tweaks.gsc` (plain text; the client needs compiled
  bytecode, not raw source).
- Compiled output goes in `t7x/scripts_library/zm/` (only staged into the running
  server while a zombies preset is active — see
  [`t7x/scripts_library/README.md`](t7x/scripts_library/README.md) for the full
  dvar table, why scripts are staged per-mode, and how to compile your own).

## 7. Custom client: t7x vs boiii

The `CLIENT` variable in `.env` selects the client:

- `CLIENT=t7x` — **works** (server starts, map loads, port opens).
- `CLIENT=boiii` — hangs at startup without writing any log. EZZBOIII shipped an
  update that broke server hosting; retry once it is fixed upstream.

Both use the **same server files and the same config**, so switching costs nothing.

## 8. Hiding your IP (playit.gg tunnel)

BO3 talks UDP, so a normal reverse proxy (nginx, Traefik...) can't front it — a
UDP tunnel can. [playit.gg](https://playit.gg) is free and gives players an
address to connect to instead of your real IP, with no router port-forward.

1. Create a free account at [playit.gg](https://playit.gg/account) and add a
   **Docker**-type agent (not Windows — no installer needed, just a key).
   It gives you a `SECRET_KEY`.
2. Put it in `.env`: `PLAYIT_SECRET_KEY=<the key>`.
3. `docker compose up -d` — the `playit` service starts automatically
   alongside `bo3` (no separate step needed).
4. In the playit.gg dashboard, create a **UDP** tunnel:
   - Local address: `bo3:28960` (the compose service name + your `GAME_PORT`;
     they share a Docker network, so this resolves without any host config).
     Don't use the `network_mode: host` snippet playit.gg's own wizard
     suggests — on Docker Desktop for Windows that breaks UDP entirely.
   - It gives you a public address like `xyz.joinmc.link:12345` — give that to
     your friends instead of your IP.

Expect slightly higher ping than a direct connection (one extra relay hop) —
that's the trade-off for not exposing your IP or touching your router.

## 9. Resources and performance

The container runs **unlimited** by default: it can use everything the Docker VM
exposes (the server itself needs roughly 1.5 GB). On Docker Desktop the real cap is
the WSL2 VM, configurable in `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=24GB
processors=16
```

Then run `wsl --shutdown` and restart Docker Desktop. Optional per-container limits
are documented (commented out) in `docker-compose.yml`.

## 10. Notes and troubleshooting

- **Port**: `27017` UDP+TCP by default. Forward it on your router to play over the
  internet, or use the [playit.gg tunnel](#8-hiding-your-ip-playitgg-tunnel) / a VPN
  mesh (Tailscale/ZeroTier) to avoid exposing your IP.
- **Missing maps**: some maps (for example Zombies Chronicles, `zm_tomb`) are not part
  of the dedicated server download. Their `.ff`/`.fd` files must be copied in from a
  full game installation. Only `.ff`/`.fd` are needed — a dedicated server renders
  nothing, so the large `.xpak` asset files are not required.
- **Startup hang under Wine**: set `USE_XVFB=1` in `.env` to provide a virtual display.
