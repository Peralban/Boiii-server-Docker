// =====================================================================
//  zm_tweaks.gsc  -  Toggleable zombies tweaks for a t7x dedicated server
//
//  Every feature is driven by a dvar, so the same script covers a normal
//  game (all defaults) up to full cheats. Change them live over RCON, then
//  reload with `map_restart`:
//
//     rcon set zm_money_multiplier 2      // 2x points from kills (native scalar)
//     rcon set zm_starting_money 5000     // bonus points on spawn
//     rcon set zm_no_perk_limit 1         // allow up to 9 perks
//     rcon set zm_perk_drop_chance 5      // 5% chance a kill drops a free perk
//     rcon set zm_godmode 1               // invulnerable players
//     rcon set zm_infinite_ammo 1         // never reload / no ammo cost
//     rcon map_restart                    // apply
//
//  Defaults below = a completely normal game.
//
//  Structure and API calls are based on verified real T7 zombies GSC:
//  system::register / callback::on_connect / callback::on_start_gametype
//  (github.com/sabotack/t7-boiii-server-gsc, real running server mod), and
//  zm_score::add_to_player_score, zm_perks::give_perk(perk,bought),
//  zm_spawner::register_zombie_death_event_callback, and the native
//  level.zombie_vars[team]["zombie_point_scalar"] multiplier (BO3 source
//  reference via bo3explorer.zeroy.com). Still SOURCE: compile before use.
// =====================================================================

#include scripts\shared\callbacks_shared;
#include scripts\shared\system_shared;
#include scripts\zm\_zm_perks;
#include scripts\zm\_zm_spawner;
#include scripts\zm\_zm_score;

#namespace zm_tweaks;

function autoexec __init__sytem__()
{
    system::register( "zm_tweaks", ::__init__, undefined, undefined );
}

function __init__()
{
    // Register default values (only used if the dvar isn't already set).
    set_default( "zm_money_multiplier", "1" );
    set_default( "zm_starting_money",   "0" );
    set_default( "zm_no_perk_limit",    "0" );
    set_default( "zm_perk_drop_chance", "0" );
    set_default( "zm_godmode",          "0" );
    set_default( "zm_infinite_ammo",    "0" );

    callback::on_start_gametype( ::initGametype );
    callback::on_connect( ::onPlayerConnectMain );
    zm_spawner::register_zombie_death_event_callback( ::onZombieDeath );
}

function set_default( name, value )
{
    if ( GetDvarString( name ) == "" )
        SetDvar( name, value );
}

// ---------------------------------------------------------------------
// Level-wide setup, re-applied every round/gametype start.
function initGametype()
{
    if ( GetDvarInt( "zm_no_perk_limit" ) == 1 )
        level.perk_purchase_limit = 9;
}

// ---------------------------------------------------------------------
function onPlayerConnectMain()
{
    self endon( "disconnect" );
    self waittill( "spawned_player" );
    self thread onPlayerSpawnedMain();
}

function onPlayerSpawnedMain()
{
    self endon( "disconnect" );

    // Native points multiplier (per-team scalar used by the score system).
    mult = GetDvarFloat( "zm_money_multiplier" );
    if ( mult > 0 && IsDefined( self.team ) )
        level.zombie_vars[ self.team ][ "zombie_point_scalar" ] = mult;

    // Bonus starting points.
    starting = GetDvarInt( "zm_starting_money" );
    if ( starting > 0 )
        self zm_score::add_to_player_score( starting );

    self thread godmode_loop();
    self thread infinite_ammo_loop();
}

function godmode_loop()
{
    self endon( "disconnect" );
    was_on = false;
    while ( true )
    {
        wait 0.5;
        on = ( GetDvarInt( "zm_godmode" ) == 1 );
        if ( on && !was_on )
            self EnableInvulnerability();
        else if ( !on && was_on )
            self DisableInvulnerability();
        was_on = on;
    }
}

function infinite_ammo_loop()
{
    self endon( "disconnect" );
    while ( true )
    {
        wait 1;
        if ( GetDvarInt( "zm_infinite_ammo" ) == 1 )
        {
            weapons = self GetWeaponsList();
            foreach ( w in weapons )
                self GiveMaxAmmo( w );
        }
    }
}

// ---------------------------------------------------------------------
// Perk drops: on each zombie kill, a chance to grant the killer a free perk.
// Runs on `self` = the zombie that died; self.attacker = the killer.
function onZombieDeath()
{
    if ( !IsDefined( self.attacker ) || !IsPlayer( self.attacker ) )
        return;

    chance = GetDvarInt( "zm_perk_drop_chance" );
    if ( chance <= 0 )
        return;

    if ( RandomInt( 100 ) < chance )
        self.attacker thread give_random_perk();
}

function give_random_perk()
{
    self endon( "disconnect" );
    perks = array( "specialty_armorvest", "specialty_quickrevive",
                   "specialty_fastreload", "specialty_rof",
                   "specialty_deadshot", "specialty_additionalprimaryweapon" );
    perk = perks[ RandomInt( perks.size ) ];
    self zm_perks::give_perk( perk, false );
}
