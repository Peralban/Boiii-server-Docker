# =============================================================================
#  Starts the BO3 server, then opens an RCON terminal once it is ready.
#
#  Usage:
#     .\start.ps1            -> start + open the RCON terminal
#     .\start.ps1 -NoRcon    -> start only (no terminal)
#     .\start.ps1 -Logs      -> start + follow the logs instead of RCON
# =============================================================================
param(
    [switch]$NoRcon,
    [switch]$Logs
)

Write-Host "==> Starting the BO3 server..." -ForegroundColor Cyan
docker compose up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "Startup failed. Make sure Docker Desktop is running." -ForegroundColor Red
    exit 1
}

if ($NoRcon -and -not $Logs) {
    Write-Host "Server started in the background." -ForegroundColor Green
    Write-Host "  Logs : docker logs -f bo3-boiii"
    Write-Host "  RCON : docker compose exec bo3 rcon"
    exit 0
}

# Loading the map takes a while, so wait until the server answers RCON.
Write-Host "==> Waiting for the map to load (can take ~1 min)..." -ForegroundColor Cyan
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    $out = docker compose exec -T bo3 rcon status 2>$null | Out-String
    if ($out -match "map:") { $ready = $true; break }
    Start-Sleep -Seconds 3
}

if (-not $ready) {
    Write-Host "The server did not answer RCON in time." -ForegroundColor Yellow
    Write-Host "Troubleshoot with: docker logs -f bo3-boiii"
    exit 1
}

Write-Host "==> Server ready!" -ForegroundColor Green

if ($Logs) {
    docker logs -f bo3-boiii
} else {
    Write-Host ""
    docker compose exec bo3 rcon
}
