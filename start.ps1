# =============================================================================
#  Starts the BO3 server, then opens an RCON terminal once it is ready.
#
#  Typing `switch <preset>` inside the RCON CLI writes a request that this
#  script picks up once the CLI exits: it restarts the server with that
#  preset and reopens the CLI automatically, looping until you type `exit`.
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

function Wait-ForServerReady {
    Write-Host "==> Waiting for the map to load (can take ~1 min)..." -ForegroundColor Cyan
    for ($i = 0; $i -lt 60; $i++) {
        $out = docker compose exec -T bo3 rcon status 2>$null | Out-String
        if ($out -match "map:") { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}

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

if (-not (Wait-ForServerReady)) {
    Write-Host "The server did not answer RCON in time." -ForegroundColor Yellow
    Write-Host "Troubleshoot with: docker logs -f bo3-boiii"
    exit 1
}

Write-Host "==> Server ready!" -ForegroundColor Green

if ($Logs) {
    docker logs -f bo3-boiii
    exit 0
}

$switchFile = Join-Path $PSScriptRoot "config\.switch_request"
while ($true) {
    Write-Host ""
    docker compose exec bo3 rcon
    Write-Host "(rcon exited, code $LASTEXITCODE - checking for a switch request...)" -ForegroundColor DarkGray

    if (-not (Test-Path $switchFile)) {
        Write-Host "(no switch request found at $switchFile)" -ForegroundColor DarkGray
        break
    }

    $preset = (Get-Content $switchFile -Raw).Trim()
    Remove-Item $switchFile -Force
    Write-Host ""
    Write-Host "==> Switch requested: '$preset'" -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "switch.ps1") $preset

    if (-not (Wait-ForServerReady)) {
        Write-Host "The server did not answer RCON in time after switching." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "==> Server ready!" -ForegroundColor Green
}
