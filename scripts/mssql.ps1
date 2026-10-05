#Requires -Version 7.0
<#
.SYNOPSIS
    SQL Server 2022 on WSL containers (wslc). Standalone recipe: independent of the other recipes.

.DESCRIPTION
    Resources:  container wslc-mssql, volume wslc-mssql-data (labelled wslc-recipes=mssql)
    Endpoint:   127.0.0.1,<MSSQL_PORT>  (login sa)
    Management: SSMS on the Windows host -> scripts/mssql-ssms.ps1
    Overrides:  MSSQL_* keys in <repo>/.env (see .env.example)

.EXAMPLE
    ./scripts/mssql.ps1 up
    ./scripts/mssql.ps1 shell
    ./scripts/mssql.ps1 reset
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('pull', 'up', 'stop', 'down', 'reset', 'status', 'logs', 'shell', 'info')]
    [string] $Action,

    # Seconds to wait for SQL Server to accept connections on `up`.
    [int] $Timeout = 120
)

$ErrorActionPreference = 'Stop'

# --- configuration (defaults, overridable from <repo>/.env) ---------------------

$Config = [ordered]@{
    MSSQL_IMAGE       = 'mcr.microsoft.com/mssql/server:2022-latest'
    MSSQL_PORT        = '1433'
    MSSQL_SA_PASSWORD = 'Dev_Passw0rd!'
    MSSQL_PID         = 'Developer'
    MSSQL_MEMORY      = '2G'
}

$envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
if (Test-Path $envFile) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$' -and $Config.Contains($Matches[1])) {
            $Config[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
        }
    }
}

$Container = 'wslc-mssql'
$Volume = 'wslc-mssql-data'
# Marks everything this recipe creates, so scripts/clean.ps1 can find it.
$Label = 'wslc-recipes=mssql'
$Sqlcmd = @('/opt/mssql-tools18/bin/sqlcmd', '-S', 'localhost', '-U', 'sa', '-P', $Config.MSSQL_SA_PASSWORD, '-C')

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

function Get-ContainerState([string] $Name) {
    $match = & wslc list --all --format json 2>$null |
        Where-Object { $_ } |
        ForEach-Object { $_ | ConvertFrom-Json } |
        Where-Object { $_.Names -eq $Name } |
        Select-Object -First 1
    if ($match) { $match.State } else { $null }
}

function Wait-Ready {
    $deadline = (Get-Date).AddSeconds($Timeout)
    Write-Host "    waiting for $Container to accept connections" -NoNewline
    while ((Get-Date) -lt $deadline) {
        & wslc exec $Container @Sqlcmd -l 2 -Q 'SELECT 1' *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host ' ready' -ForegroundColor Green; return }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 2
    }
    Write-Host ''
    throw "$Container not ready after $Timeout s. Check the logs: ./scripts/mssql.ps1 logs"
}

function Remove-Container {
    if (Get-ContainerState $Container) {
        Write-Step "removing container $Container (data volume kept)"
        Invoke-Wslc remove --force --volumes $Container | Out-Null
    }
}

function Show-Info {
    Write-Host ''
    Write-Host 'SQL Server (use 127.0.0.1, not "localhost" - wslc publishes on IPv4 loopback only)' -ForegroundColor Yellow
    Write-Host "  Server:   127.0.0.1,$($Config.MSSQL_PORT)"
    Write-Host '  Login:    sa'
    Write-Host "  Password: $($Config.MSSQL_SA_PASSWORD)"
    Write-Host "  ADO.NET:  Server=127.0.0.1,$($Config.MSSQL_PORT);User Id=sa;Password=$($Config.MSSQL_SA_PASSWORD);TrustServerCertificate=True"
    Write-Host '  SSMS:     ./scripts/mssql-ssms.ps1  (tick "Trust server certificate")'
}

# --- actions ---------------------------------------------------------------------

if (-not (Get-Command wslc -ErrorAction SilentlyContinue)) {
    throw 'wslc not found. Update WSL (wsl --update) to a version that ships WSL containers.'
}

switch ($Action) {
    'pull' { Invoke-Wslc pull $Config.MSSQL_IMAGE }
    'up' {
        $state = Get-ContainerState $Container
        if ($state -eq 'running') {
            Write-Step "$Container already running"
        }
        elseif ($state) {
            Write-Step "starting existing $Container"
            Invoke-Wslc start $Container | Out-Null
        }
        else {
            if (-not (Test-WslcObject volume $Volume)) {
                Write-Step "creating volume $Volume"
                Invoke-Wslc volume create --label $Label $Volume | Out-Null
            }
            Write-Step "creating $Container from $($Config.MSSQL_IMAGE)"
            Invoke-Wslc run -d --name $Container --hostname $Container --label $Label `
                -p "$($Config.MSSQL_PORT):1433" `
                -v "${Volume}:/var/opt/mssql" `
                --memory $Config.MSSQL_MEMORY `
                -e 'ACCEPT_EULA=Y' `
                -e "MSSQL_SA_PASSWORD=$($Config.MSSQL_SA_PASSWORD)" `
                -e "MSSQL_PID=$($Config.MSSQL_PID)" `
                $Config.MSSQL_IMAGE | Out-Null
        }
        Wait-Ready
        Show-Info
    }
    'stop' {
        if ((Get-ContainerState $Container) -eq 'running') { Write-Step "stopping $Container"; Invoke-Wslc stop $Container | Out-Null }
    }
    'down' { Remove-Container }
    'reset' {
        Remove-Container
        if (Test-WslcObject volume $Volume) { Write-Step "removing volume $Volume"; Invoke-Wslc volume remove $Volume | Out-Null }
    }
    'status' {
        $state = Get-ContainerState $Container
        Write-Host ('{0,-26} {1}' -f $Container, ($state ?? 'not created'))
        Write-Host ('{0,-26} {1}' -f $Volume, ((Test-WslcObject volume $Volume) ? 'exists' : 'not created'))
    }
    'logs' { Invoke-Wslc logs $Container }
    'shell' { & wslc exec -it $Container @Sqlcmd }
    'info' { Show-Info }
}
