#Requires -Version 7.0
<#
.SYNOPSIS
    PostgreSQL + TimescaleDB extension + pgAdmin on WSL containers (wslc). Standalone recipe: independent of the other recipes.

.DESCRIPTION
    Resources:  containers wslc-timescale, wslc-timescale-pgadmin
                volumes    wslc-timescale-18-data, wslc-timescale-pgadmin-data
                network    wslc-timescale-net
                (all labelled wslc-recipes=<recipe>)
    Endpoints:  TimescaleDB 127.0.0.1:<TIMESCALE_PORT>, pgAdmin http://127.0.0.1:<TIMESCALE_PGADMIN_PORT>
    Overrides:  TIMESCALE_* keys in <repo>/.env (see .env.example)

.EXAMPLE
    ./scripts/postgresql+timescale.ps1 up
    ./scripts/postgresql+timescale.ps1 shell
    ./scripts/postgresql+timescale.ps1 logs pgadmin
    ./scripts/postgresql+timescale.ps1 pgadmin      # open pgAdmin in the browser
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('pull', 'up', 'stop', 'down', 'reset', 'status', 'logs', 'shell', 'info', 'pgadmin')]
    [string] $Action,

    # Container targeted by `logs` and `shell`.
    [Parameter(Position = 1)]
    [ValidateSet('db', 'pgadmin')]
    [string] $Target = 'db',

    # Seconds to wait for each container to become ready on `up`.
    [int] $Timeout = 120
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

# --- configuration (defaults, overridable from <repo>/.env) ---------------------

$Config = [ordered]@{
    TIMESCALE_IMAGE         = 'timescale/timescaledb:latest-pg18'
    TIMESCALE_PORT          = '5433'
    TIMESCALE_USER          = 'postgres'
    TIMESCALE_PASSWORD      = 'postgres'
    TIMESCALE_DB            = 'tsdb'
    TIMESCALE_PGADMIN_IMAGE = 'dpage/pgadmin4:latest'
    TIMESCALE_PGADMIN_PORT  = '5051'
}

$envFile = Join-Path $RepoRoot '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$' -and $Config.Contains($Matches[1])) {
            $Config[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
        }
    }
}

$Setup = 'timescale'
$DisplayName = 'TimescaleDB'
$Network = "wslc-$Setup-net"
$Db = @{ Name = "wslc-$Setup"; Volume = "wslc-$Setup-18-data" }
$PgAdmin = @{ Name = "wslc-$Setup-pgadmin"; Volume = "wslc-$Setup-pgadmin-data" }
# Marks everything this recipe creates, so scripts/clean.ps1 can find it.
$Label = "wslc-recipes=$Setup"
$PgAdminUrl = "http://127.0.0.1:$($Config.TIMESCALE_PGADMIN_PORT)"
# Generated (git-ignored) so it always matches the configured user/db.
$ServersJson = Join-Path $RepoRoot ".local\$Setup\pgadmin-servers.json"

# --- helpers ---------------------------------------------------------------------

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# Plain function (no param block) so wslc flags like -v/-d are never bound as PowerShell parameters.
function Invoke-Wslc {
    & wslc @args
    if ($LASTEXITCODE -ne 0) { throw "wslc $($args[0]) failed (exit $LASTEXITCODE)" }
}

function Test-WslcObject([string] $Kind, [string] $Name) {
    & wslc $Kind inspect $Name *> $null
    return $LASTEXITCODE -eq 0
}

function Get-ContainerInfo([string] $Name) {
    & wslc list --all --format json 2>$null |
        Where-Object { $_ } |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object { $_.Names -eq $Name } |
        Select-Object -First 1
}

function Get-ContainerState([string] $Name) {
    (Get-ContainerInfo $Name).State
}

function Wait-Until([string] $Name, [scriptblock] $Probe) {
    $deadline = (Get-Date).AddSeconds($Timeout)
    Write-Host "    waiting for $Name to accept connections" -NoNewline
    while ((Get-Date) -lt $deadline) {
        if (& $Probe) { Write-Host ' ready' -ForegroundColor Green; return }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 2
    }
    Write-Host ''
    throw "$Name not ready after $Timeout s. Check the logs: ./scripts/$(Split-Path $PSCommandPath -Leaf) logs"
}

# Creates the container with $RunArgs, or starts it if it already exists.
function Start-Container([string] $Name, [string[]] $RunArgs) {
    $state = Get-ContainerState $Name
    if ($state -eq 'running') { Write-Step "$Name already running" }
    elseif ($state) { Write-Step "starting existing $Name"; Invoke-Wslc start $Name | Out-Null }
    else { Write-Step "creating $Name"; Invoke-Wslc run -d --name $Name --hostname $Name --network $Network --label $Label @RunArgs | Out-Null }
}

function Remove-Container([string] $Name) {
    if (Get-ContainerState $Name) {
        Write-Step "removing container $Name (data volume kept)"
        Invoke-Wslc remove --force --volumes $Name | Out-Null
    }
}

function Write-ServersJson {
    $servers = @{
        Servers = @{
            '1' = [ordered]@{
                Name          = $DisplayName
                Group         = 'wslc-recipes'
                Host          = $Db.Name   # resolved over $Network
                Port          = 5432
                MaintenanceDB = $Config.TIMESCALE_DB
                Username      = $Config.TIMESCALE_USER
                SSLMode       = 'prefer'
            }
        }
    }
    New-Item -ItemType Directory -Force (Split-Path $ServersJson) | Out-Null
    $servers | ConvertTo-Json -Depth 5 | Set-Content $ServersJson
}

function Show-Info {
    Write-Host ''
    Write-Host "$DisplayName (use 127.0.0.1, not `"localhost`" - wslc publishes on IPv4 loopback only)" -ForegroundColor Yellow
    Write-Host "  URI:      postgresql://$($Config.TIMESCALE_USER):$($Config.TIMESCALE_PASSWORD)@127.0.0.1:$($Config.TIMESCALE_PORT)/$($Config.TIMESCALE_DB)"
    Write-Host "  Npgsql:   Host=127.0.0.1;Port=$($Config.TIMESCALE_PORT);Database=$($Config.TIMESCALE_DB);Username=$($Config.TIMESCALE_USER);Password=$($Config.TIMESCALE_PASSWORD)"
    Write-Host "  pgAdmin:  $PgAdminUrl  (server pre-registered; password: $($Config.TIMESCALE_PASSWORD))"
    Write-Host "  Extension timescaledb is enabled in '$($Config.TIMESCALE_DB)'; elsewhere run: CREATE EXTENSION IF NOT EXISTS timescaledb;"
}

# --- actions ---------------------------------------------------------------------

if (-not (Get-Command wslc -ErrorAction SilentlyContinue)) {
    throw 'wslc not found. Update WSL (wsl --update) to a version that ships WSL containers.'
}

$TargetName = if ($Target -eq 'pgadmin') { $PgAdmin.Name } else { $Db.Name }

switch ($Action) {
    'pull' {
        Invoke-Wslc pull $Config.TIMESCALE_IMAGE
        Invoke-Wslc pull $Config.TIMESCALE_PGADMIN_IMAGE
    }
    'up' {
        $existing = Get-ContainerInfo $Db.Name
        if ($existing -and ($existing.Image -notlike "*$($Config.TIMESCALE_IMAGE)*" -or -not (Test-WslcObject volume $Db.Volume))) {
            throw "$($Db.Name) uses a different image or data volume. Run 'task timescale:down' to remove it while keeping its data, then run 'task timescale:up' to create $($Config.TIMESCALE_IMAGE). Migrate data separately."
        }
        if (-not (Test-WslcObject network $Network)) {
            Write-Step "creating network $Network"
            Invoke-Wslc network create --label $Label $Network | Out-Null
        }
        foreach ($volume in $Db.Volume, $PgAdmin.Volume) {
            if (-not (Test-WslcObject volume $volume)) { Write-Step "creating volume $volume"; Invoke-Wslc volume create --label $Label $volume | Out-Null }
        }

        Start-Container $Db.Name @(
            '-p', "$($Config.TIMESCALE_PORT):5432",
            '-v', "$($Db.Volume):/var/lib/postgresql",
            '-e', "POSTGRES_USER=$($Config.TIMESCALE_USER)",
            '-e', "POSTGRES_PASSWORD=$($Config.TIMESCALE_PASSWORD)",
            '-e', "POSTGRES_DB=$($Config.TIMESCALE_DB)",
            $Config.TIMESCALE_IMAGE)
        Wait-Until $Db.Name {
            & wslc exec $Db.Name pg_isready -U $Config.TIMESCALE_USER -d $Config.TIMESCALE_DB *> $null
            $LASTEXITCODE -eq 0
        }

        Write-ServersJson
        Start-Container $PgAdmin.Name @(
            '-p', "$($Config.TIMESCALE_PGADMIN_PORT):80",
            '-v', "$($PgAdmin.Volume):/var/lib/pgadmin",
            '-v', "${ServersJson}:/pgadmin4/servers.json:ro",
            '-e', 'PGADMIN_DEFAULT_EMAIL=admin@local.dev',
            '-e', 'PGADMIN_DEFAULT_PASSWORD=admin',
            '-e', 'PGADMIN_CONFIG_SERVER_MODE=False',
            '-e', 'PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False',
            $Config.TIMESCALE_PGADMIN_IMAGE)
        Wait-Until $PgAdmin.Name {
            try { Invoke-WebRequest "$PgAdminUrl/misc/ping" -UseBasicParsing -TimeoutSec 3 | Out-Null; $true } catch { $false }
        }

        Show-Info
    }
    'stop' {
        foreach ($name in $PgAdmin.Name, $Db.Name) {
            if ((Get-ContainerState $name) -eq 'running') { Write-Step "stopping $name"; Invoke-Wslc stop $name | Out-Null }
        }
    }
    'down' {
        Remove-Container $PgAdmin.Name
        Remove-Container $Db.Name
    }
    'reset' {
        Remove-Container $PgAdmin.Name
        Remove-Container $Db.Name
        foreach ($volume in $PgAdmin.Volume, $Db.Volume) {
            if (Test-WslcObject volume $volume) { Write-Step "removing volume $volume"; Invoke-Wslc volume remove $volume | Out-Null }
        }
        if (Test-WslcObject network $Network) { Write-Step "removing network $Network"; Invoke-Wslc network remove $Network | Out-Null }
    }
    'status' {
        foreach ($name in $Db.Name, $PgAdmin.Name) { Write-Host ('{0,-36} {1}' -f $name, ((Get-ContainerState $name) ?? 'not created')) }
        foreach ($volume in $Db.Volume, $PgAdmin.Volume) { Write-Host ('{0,-36} {1}' -f $volume, ((Test-WslcObject volume $volume) ? 'exists' : 'not created')) }
    }
    'logs' { Invoke-Wslc logs $TargetName }
    'shell' {
        if ($Target -eq 'pgadmin') { & wslc exec -it $TargetName /bin/sh }
        else { & wslc exec -it $TargetName psql -U $Config.TIMESCALE_USER -d $Config.TIMESCALE_DB }
    }
    'info' { Show-Info }
    'pgadmin' { Start-Process $PgAdminUrl }
}
