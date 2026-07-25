# =============================================================================
#  Switch the server between multiplayer / zombies / campaign co-op, or any
#  custom preset config in config/. BO3 cannot switch mode live (it crashes),
#  so this changes SERVER_CFG in .env and recreates the container (~15s).
#
#  Usage:
#     .\switch.ps1 mp             -> multiplayer  (server.cfg)
#     .\switch.ps1 zm             -> zombies      (server_zm.cfg)
#     .\switch.ps1 cp             -> campaign co-op (server_cp.cfg)
#     .\switch.ps1 snipe1v1       -> preset: config/server_snipe1v1.cfg
#     .\switch.ps1 7v7bots        -> preset: config/server_7v7bots.cfg
#     (any other name maps to config/server_<name>.cfg if it exists)
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$Mode
)

$fixed = @{ mp = 'server.cfg'; zm = 'server_zm.cfg'; cp = 'server_cp.cfg' }
if ($fixed.ContainsKey($Mode)) {
    $cfg = $fixed[$Mode]
} else {
    $cfg = "server_$Mode.cfg"
    if (-not (Test-Path "config\$cfg")) {
        Write-Host "Unknown mode/preset '$Mode' (no config\$cfg found)." -ForegroundColor Red
        exit 1
    }
}

if (-not (Test-Path .env)) {
    Write-Host "No .env found. Copy .env.example to .env first." -ForegroundColor Red
    exit 1
}

# Rewrite (or add) the SERVER_CFG line in .env
$content = Get-Content .env
if ($content -match '^SERVER_CFG=') {
    $content = $content -replace '^SERVER_CFG=.*', "SERVER_CFG=$cfg"
} else {
    $content += "SERVER_CFG=$cfg"
}
$content | Set-Content .env

Write-Host "==> Mode/preset: $Mode  (SERVER_CFG=$cfg)" -ForegroundColor Cyan
Write-Host "==> Recreating the container..." -ForegroundColor Cyan
docker compose up -d --force-recreate

Write-Host "==> Done. Follow the load with: docker logs -f bo3-boiii" -ForegroundColor Green
