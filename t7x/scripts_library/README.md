# Custom GSC script library

Compiled GSC scripts, organized **by game mode**:

```
t7x/scripts_library/
├── all/    scripts safe to load in every mode
├── mp/     multiplayer-only scripts
├── zm/     zombies-only scripts   <- zm_tweaks.gsc lives here
└── cp/     campaign co-op-only scripts
```

At every startup, the entrypoint copies `all/*.gsc` plus `<active_mode>/*.gsc`
into `UnrankedServer/t7x/custom_scripts/` (derived from `SERVER_CFG` in `.env`:
`server.cfg` → mp, `server_zm.cfg` → zm, `server_cp.cfg` → cp). Any other
mode's scripts are left out.

## Why this exists (real bug, found and fixed)

Zombies-only scripts `#include` zombies-only engine modules
(`scripts\zm\_zm_perks`, `_zm_spawner`, `_zm_score`, ...). Those `#include`
directives are resolved when the client loads the script — **not**
conditionally at runtime — so if a zombies script sits in `custom_scripts/`
while the server is running multiplayer or campaign co-op, those modules
aren't available and the script load aborts. That aborted the *entire* game
process (exit code 0, immediately restarted by `restart: unless-stopped`),
which is why the server failed to start in multiplayer once `zm_tweaks.gsc`
was dropped into `custom_scripts/`.

(Separately: `Error: Could not find scriptparsetree "custom_scripts/X.gsc"` is
a harmless, cosmetic warning whenever a script is added this way — confirmed
by the t7x/AlterWare community. It is **not** what breaks multiplayer; the
zm-only `#include` failing to resolve outside zombies mode is.)

**The fix**: never let a mode-specific script be present in `custom_scripts/`
while a different mode is running. This library + the entrypoint's
`stage_custom_scripts()` step does that automatically.

## The catch: GSC must be compiled

t7x loads **compiled** `.gsc` files, not raw text:

```
write .gsc (source)  ->  compile  ->  drop the compiled .gsc in the right mode folder  ->  toggle via RCON
```

Sources live in `gsc_source/` at the project root (kept out of any
loaded/mounted folder — it's plain text, t7x needs compiled bytecode). To
compile you need one of:

- **BO3 Mod Tools** (free, from Steam → Library → Tools → "Call of Duty: Black
  Ops III - Mod Tools"). Full pipeline: put the script in a mod's
  `scripts/zm/` folder, reference it in the zone file, build, then extract the
  compiled `.gscc` with **Cerberus** and rename it to `.gsc`.
- **t7-compiler** (https://github.com/shiversoftdev/t7-compiler) — lighter,
  standalone. Run `DebugCompiler.exe`, press `C`, give it the source folder
  path and `T7`. Output is `compiled.gscc` next to the tool; rename it `.gsc`.

## Adding your own script

1. Write the source under `gsc_source/`.
2. Compile it.
3. Drop the compiled `.gsc` into the matching mode folder here
   (`zm/`, `mp/`, `cp/`, or `all/` if it truly works everywhere — i.e. it
   doesn't `#include` any mode-specific module).
4. `docker compose restart bo3` (or switch mode with `switch.sh`/`switch.ps1`)
   — the entrypoint stages it automatically.

## zm_tweaks.gsc

Toggleable zombies tweaks (money multiplier, starting money, perk limit, perk
drops, godmode, infinite ammo), all driven by dvars settable over RCON:

```bash
docker compose exec bo3 rcon set zm_money_multiplier 2
docker compose exec bo3 rcon set zm_perk_drop_chance 5
docker compose exec bo3 rcon set zm_godmode 1
docker compose exec bo3 rcon map_restart      # reload to apply
```

Back to a completely normal game in one command:

```bash
docker compose exec bo3 rcon reset
```

| Dvar | Default | Effect |
|------|---------|--------|
| `zm_money_multiplier` | 1 | Points scalar (native `zombie_point_scalar`), decimals OK: `1.5` |
| `zm_starting_money`   | 0 | Bonus points on spawn |
| `zm_no_perk_limit`    | 0 | Allow up to 9 perks (`level.perk_purchase_limit`) |
| `zm_perk_drop_chance` | 0 | % chance a killed zombie drops a free perk |
| `zm_godmode`          | 0 | Invulnerable players |
| `zm_infinite_ammo`    | 0 | Never run out of ammo |

All defaults = a normal game. Set them in `config/server_zm.cfg` to make them
persistent (e.g. `set zm_money_multiplier "1.5"`).

The script's structure (`system::register`, `callback::on_connect`,
`callback::on_start_gametype`) and calls (`zm_score::add_to_player_score`,
`zm_perks::give_perk(perk, bought)`,
`zm_spawner::register_zombie_death_event_callback`,
`level.zombie_vars[team]["zombie_point_scalar"]`) are based on a real, running
T7 dedicated server mod ([sabotack/t7-boiii-server-gsc](https://github.com/sabotack/t7-boiii-server-gsc))
and the decompiled BO3 source reference (bo3explorer.zeroy.com), not guessed.
