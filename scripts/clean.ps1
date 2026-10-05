#Requires -Version 7.0
<#
.SYNOPSIS
    Stop and remove every wslc resource that belongs to this repo, across all recipes.

.DESCRIPTION
    A container, network or volume belongs to the repo when it carries the `wslc-recipes` label (the
    recipe scripts set it on everything they create) or its name follows a recipe's naming scheme
    (wslc-mssql*, wslc-postgresql*, wslc-timescale*). The name match also catches resources created
    before the label existed, or by hand while experimenting.

    Default:   stop + remove containers, remove networks. Data volumes are kept.
    -Volumes:  also delete the data volumes and the generated .local/ folder.

.EXAMPLE
    ./scripts/clean.ps1
    ./scripts/clean.ps1 -Volumes
#>
[CmdletBinding()]
param(
    # Also delete data volumes and generated files (all recipes' data is lost).
    [switch] $Volumes
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent

$Label = 'wslc-recipes'
# Keep in sync with the recipe names in scripts/ when adding a recipe.
$NamePattern = '^wslc-(mssql|postgresql|timescale)(-|$)'

# --- helpers ---------------------------------------------------------------------

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# Plain function (no param block) so wslc flags like -v/-f are never bound as PowerShell parameters.
function Invoke-Wslc {
    & wslc @args
    if ($LASTEXITCODE -ne 0) { throw "wslc $($args[0]) failed (exit $LASTEXITCODE)" }
}

function Read-WslcJson {
    & wslc @args --format json 2>$null | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }
}

# Objects of one kind (from the given list command) that are labelled or named as this repo's.
function Get-RepoObject([string] $NameField, [string[]] $ListCommand) {
    $labelled = @(Read-WslcJson @ListCommand --filter "label=$Label" | ForEach-Object $NameField)
    Read-WslcJson @ListCommand | Where-Object { $_.$NameField -match $NamePattern -or $_.$NameField -in $labelled }
}

# --- clean -----------------------------------------------------------------------

if (-not (Get-Command wslc -ErrorAction SilentlyContinue)) {
    throw 'wslc not found. Update WSL (wsl --update) to a version that ships WSL containers.'
}

$containers = @(Get-RepoObject Names 'list', '--all')
$running = @($containers | Where-Object State -eq 'running' | ForEach-Object Names)
if ($running) {
    Write-Step "stopping $($running -join ', ')"
    Invoke-Wslc stop @running | Out-Null
}
if ($containers) {
    Write-Step "removing containers $($containers.Names -join ', ')"
    Invoke-Wslc remove --force --volumes @($containers.Names) | Out-Null
}

$networks = @(Get-RepoObject Name 'network', 'list' | ForEach-Object Name)
if ($networks) {
    Write-Step "removing networks $($networks -join ', ')"
    Invoke-Wslc network remove @networks | Out-Null
}

$volumeNames = @(Get-RepoObject Name 'volume', 'list' | ForEach-Object Name)
if ($Volumes) {
    if ($volumeNames) {
        Write-Step "removing volumes $($volumeNames -join ', ')"
        Invoke-Wslc volume remove @volumeNames | Out-Null
    }
    $localDir = Join-Path $RepoRoot '.local'
    if (Test-Path $localDir) {
        Write-Step 'removing generated .local/'
        Remove-Item -Recurse -Force $localDir
    }
}

if (-not ($containers -or $networks -or ($Volumes -and $volumeNames))) {
    Write-Step 'nothing to clean'
}
if (-not $Volumes -and $volumeNames) {
    Write-Host "    kept data volumes: $($volumeNames -join ', ')  (task purge deletes them)"
}
