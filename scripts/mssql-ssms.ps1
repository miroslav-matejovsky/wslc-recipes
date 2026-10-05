#Requires -Version 7.0
<#
.SYNOPSIS
    Launch SQL Server Management Studio (Windows host) connected to the wslc SQL Server container
    started by scripts/mssql.ps1.
    SSMS is a Windows GUI app; it cannot run inside a Linux container, so it connects over the published port.
#>
$ErrorActionPreference = 'Stop'

# Same default/override rule as mssql.ps1: MSSQL_PORT from <repo>/.env, else 1433.
$envFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
$portLine = if (Test-Path $envFile) { Select-String -Path $envFile -Pattern '^\s*MSSQL_PORT\s*=\s*(\d+)' | Select-Object -First 1 }
$port = if ($portLine) { $portLine.Matches[0].Groups[1].Value } else { '1433' }

# SSMS 21+ installs under Program Files, SSMS 20 and older under Program Files (x86).
$ssms = Get-ChildItem "${env:ProgramFiles}\Microsoft SQL Server Management Studio*", "${env:ProgramFiles(x86)}\Microsoft SQL Server Management Studio*" `
    -Recurse -Filter ssms.exe -ErrorAction SilentlyContinue |
    Sort-Object { $_.VersionInfo.FileVersionRaw } -Descending |
    Select-Object -First 1

if (-not $ssms) {
    Write-Warning 'SSMS not found. Install it (winget install Microsoft.SQLServerManagementStudio) or connect with any client to:'
    Write-Host "  Server: 127.0.0.1,$port   Login: sa   Trust server certificate: yes"
    exit 1
}

Write-Host "Starting $($ssms.FullName) -> 127.0.0.1,$port (login sa; enter MSSQL_SA_PASSWORD and tick 'Trust server certificate')"
Start-Process $ssms.FullName -ArgumentList '-S', "127.0.0.1,$port", '-U', 'sa'
