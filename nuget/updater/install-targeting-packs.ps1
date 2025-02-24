Set-StrictMode -version 2.0
$ErrorActionPreference = "Stop"

. $PSScriptRoot\common.ps1

try {
    $targetingPacksToInstall = Get-RequiredTargetingPacks -sdkInstallDir $env:DOTNET_INSTALL_DIR
    Install-TargetingPacks -sdkInstallDir $env:DOTNET_INSTALL_DIR -targetingPacks $targetingPacksToInstall
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
