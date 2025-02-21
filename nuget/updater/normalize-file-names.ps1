Set-StrictMode -version 2.0
$ErrorActionPreference = "Stop"

. $PSScriptRoot\common.ps1

try {
    Repair-FileCasing
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
