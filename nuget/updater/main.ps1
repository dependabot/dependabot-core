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
    Write-Host "Job: $($job | ConvertTo-Json -Depth 99)"
    if (Test-Path (Join-Path $env:DEPENDABOT_REPO_CONTENTS_PATH ".git")) {
        # this can happen if the CLI specified the `--local` option
        Write-Host "Git repository already exists, skipping clone."
        $script:operationExitCode = 0
    }
    else {
        & $updaterTool clone `
            --job-path $env:DEPENDABOT_JOB_PATH `
            --repo-contents-path $env:DEPENDABOT_REPO_CONTENTS_PATH `
            --api-url $env:DEPENDABOT_API_URL `
            --job-id $env:DEPENDABOT_JOB_ID
        $script:operationExitCode = $LASTEXITCODE
    }

    if (($script:operationExitCode -eq 0) -and ("$env:DEPENDABOT_CASE_INSENSITIVE_REPO_CONTENTS_PATH" -eq "")) {
        # this only makes sense if the native clone operation succeeded and we're not running in case-insensitive mode
        Repair-FileCasing
    }
}

function Update-Files {
    # install relevant SDKs
    Install-Sdks `
        -jobFilePath $env:DEPENDABOT_JOB_PATH `
        -repoContentsPath $env:DEPENDABOT_REPO_CONTENTS_PATH `
        -dotnetInstallScriptPath $env:DOTNET_INSTALL_SCRIPT_PATH `
        -dotnetInstallDir $env:DOTNET_INSTALL_DIR
    # TODO: install workloads?

    Set-NuGetConfig

    Push-Location $env:DEPENDABOT_REPO_CONTENTS_PATH
    $baseCommitSha = git rev-parse HEAD
    Pop-Location
    Write-Host "Base commit SHA: $baseCommitSha"

    $arguments = @()
    $arguments += "run"
    $arguments += "--job-path", $env:DEPENDABOT_JOB_PATH
    $arguments += "--repo-contents-path", $env:DEPENDABOT_REPO_CONTENTS_PATH
    $arguments += "--api-url", $env:DEPENDABOT_API_URL
    $arguments += "--job-id", $env:DEPENDABOT_JOB_ID
    $arguments += "--output-path", $env:DEPENDABOT_OUTPUT_PATH
    $arguments += "--base-commit-sha", $baseCommitSha
    if ("$env:DEPENDABOT_CASE_INSENSITIVE_REPO_CONTENTS_PATH" -ne "") {
        # ensure the updater gets this optional path
        $arguments += "--case-insensitive-repo-contents-path", $env:DEPENDABOT_CASE_INSENSITIVE_REPO_CONTENTS_PATH

        # redirect the local package cache to the case-insensitive path...
        $caseInsensitiveRoot = Join-Path $env:DEPENDABOT_CASE_INSENSITIVE_REPO_CONTENTS_PATH ".."
        $env:NUGET_PACKAGES = "$caseInsensitiveRoot/.nuget/packages"
        $env:NUGET_HTTP_CACHE_PATH = "$caseInsensitiveRoot/.nuget/http-cache"
        $env:NUGET_SCRATCH = "$caseInsensitiveRoot/.nuget/scratch"
        $env:NUGET_PLUGINS_CACHE_PATH = "$caseInsensitiveRoot/.nuget/plugins-cache"

        # ...but still allow read access to the pre-populated packages
        $env:NUGET_FALLBACK_PACKAGES = "$env:DEPENDABOT_HOME/.nuget/packages"
    }

    $process = Start-Process -FilePath $updaterTool -ArgumentList $arguments -NoNewWindow -Wait -PassThru
    $process.WaitForExit()
    $script:operationExitCode = $process.ExitCode
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
