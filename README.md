# Black Ops 3 dedicated server in Docker

A headless BO3 dedicated server running under **Wine** inside a container, based on the
logic of [framilano/BlackOps3ServerInstaller](https://github.com/framilano/BlackOps3ServerInstaller).
Supports the **t7x** and **EZZBOIII** custom clients.

## Requirements

- Docker (Docker Desktop on Windows, with the WSL2 backend).
- **No Steam account required**: the dedicated server files (app 545990) download
  anonymously.

## Quick start

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

## One-command start (recommended)

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

## Monitoring

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

## RCON CLI (administration)

Control the running server (change map, kick, broadcast messages...):

```bash
docker compose exec bo3 rcon
```

A real interactive CLI: **command history** (↑/↓ arrows, persisted across
restarts), **tab-completion**, and colored output. On top of any raw RCON
command (`status`, `serverinfo`, `map_rotate`, `map mp_havoc`, `say <message>`,
`g_gametype dom`, ...), it adds:

| Command | Effect |
|---|---|
| `players` (or `ls`) | Clean player table (color codes stripped) |
| `kick <#\|name>` | Kick by number or partial name, from the last `players` list |
| `watch <command>` | Re-run a command every 2s until Ctrl-C (e.g. `watch players`) |
| `reset` | Reset all `zm_tweaks` dvars (see below) to a normal game, in one shot |
| `help` | **Adaptive**: shows bot commands in multiplayer, `zm_tweaks` dvars in zombies |
| `help maps` (or `help map`) | Full codename ↔ real name table for the active mode's maps |

Or run any single command without entering the interactive shell:

```bash
docker compose exec bo3 rcon players
docker compose exec bo3 rcon watch players
```

> **IW4MAdmin does not officially support BO3 (T7).** Only an experimental,
> partially working plugin exists for BOIII. The RCON CLI above is the
> reliable option.

### Raw RCON command reference

Any of these work as-is, either typed in the interactive CLI or as
`docker compose exec bo3 rcon <command>`:

| Category | Command | Effect |
|---|---|---|
| Info | `status` | Connected players (number, ping, name, address) |
| Info | `serverinfo` | All current server settings |
| Info | `dumpuser <name>` | Details about one player |
| Maps | `map <name>` | Load a specific map (same mode only — MP↔ZM needs `switch.sh`/`.ps1`) |
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

## Configuration

Config files live in `config/` and are **templates**: placeholders such as
`${RCON_PASSWORD}` are replaced at startup with the values from `.env`. This keeps
every secret out of version control.

| Mode | `SERVER_CFG` value |
|---|---|
| Multiplayer | `server.cfg` |
| Zombies | `server_zm.cfg` |
| Campaign co-op | `server_cp.cfg` |

Change it in `.env`, then run `docker compose up -d`.

## Custom client: t7x vs boiii

The `CLIENT` variable in `.env` selects the client:

- `CLIENT=t7x` — **works** (server starts, map loads, port opens).
- `CLIENT=boiii` — hangs at startup without writing any log. EZZBOIII shipped an
  update that broke server hosting; retry once it is fixed upstream.

Both use the **same server files and the same config**, so switching costs nothing.

## Resources

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

## Notes

- **Port**: `27017` UDP+TCP by default. Forward it on your router to play over the
  internet, or use a VPN mesh (Tailscale/ZeroTier) to avoid exposing your IP.
- **Missing maps**: some maps (for example Zombies Chronicles, `zm_tomb`) are not part
  of the dedicated server download. Their `.ff`/`.fd` files must be copied in from a
  full game installation. Only `.ff`/`.fd` are needed — a dedicated server renders
  nothing, so the large `.xpak` asset files are not required.
- **Startup hang under Wine**: set `USE_XVFB=1` in `.env` to provide a virtual display.
