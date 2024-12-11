Set-StrictMode -version 2.0
$ErrorActionPreference = "Stop"

. $PSScriptRoot\common.ps1

try {
    Install-Sdks `
        -jobFilePath $env:DEPENDABOT_JOB_PATH `
        -repoContentsPath $env:DEPENDABOT_REPO_CONTENTS_PATH `
        -dotnetInstallScriptPath $env:DOTNET_INSTALL_SCRIPT_PATH `
        -dotnetInstallDir $env:DOTNET_INSTALL_DIR
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
