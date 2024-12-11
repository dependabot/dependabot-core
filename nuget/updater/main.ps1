Set-StrictMode -version 2.0
$ErrorActionPreference = "Stop"

. $PSScriptRoot\common.ps1

$updaterTool = "$env:DEPENDABOT_NATIVE_HELPERS_PATH/nuget/NuGetUpdater/NuGetUpdater.Cli"

# Function return values in PowerShell are wacky and contain all of the output produced during the function call.
# Because of this, we need a reliable way to communicate _only_ the result of executing a single command, not its
# output.  To accomplish this the value `$operationExitCode` is introduced and explicitly tracked.  The value
# cannot be directly set, however, because it would be scoped locally to the function, so the `script:` prefix
# is added when setting the value.
$operationExitCode = 0

function Get-Files {
    $job = Get-Job -jobFilePath $env:DEPENDABOT_JOB_PATH
    Write-Host "Job: $($job | ConvertTo-Json)"
    & $updaterTool clone `
        --job-path $env:DEPENDABOT_JOB_PATH `
        --repo-contents-path $env:DEPENDABOT_REPO_CONTENTS_PATH `
        --api-url $env:DEPENDABOT_API_URL `
        --job-id $env:DEPENDABOT_JOB_ID
    $script:operationExitCode = $LASTEXITCODE
}

function Update-Files {
    # install relevant SDKs
    Install-Sdks `
        -jobFilePath $env:DEPENDABOT_JOB_PATH `
        -repoContentsPath $env:DEPENDABOT_REPO_CONTENTS_PATH `
        -dotnetInstallScriptPath $env:DOTNET_INSTALL_SCRIPT_PATH `
        -dotnetInstallDir $env:DOTNET_INSTALL_DIR
    # TODO: install workloads?

    Push-Location $env:DEPENDABOT_REPO_CONTENTS_PATH
    $baseCommitSha = git rev-parse HEAD
    Pop-Location

    & $updaterTool run `
        --job-path $env:DEPENDABOT_JOB_PATH `
        --repo-contents-path $env:DEPENDABOT_REPO_CONTENTS_PATH `
        --api-url $env:DEPENDABOT_API_URL `
        --job-id $env:DEPENDABOT_JOB_ID `
        --output-path $env:DEPENDABOT_OUTPUT_PATH `
        --base-commit-sha $baseCommitSha
    $script:operationExitCode = $LASTEXITCODE
}

try {
    Switch ($args[0]) {
        "fetch_files" { Get-Files }
        "update_files" { Update-Files }
        default { throw "unknown command: $args[0]" }
    }
    exit $operationExitCode
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
