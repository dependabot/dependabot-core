Set-StrictMode -version 2.0
$ErrorActionPreference = "Stop"

. $PSScriptRoot\common.ps1

$updaterTool = "$env:DEPENDABOT_NATIVE_HELPERS_PATH/nuget/NuGetUpdater/NuGetUpdater.Cli"
$jobString = Get-Content -Path $env:DEPENDABOT_JOB_PATH
$job = (ConvertFrom-Json -InputObject $jobString).job

# Function return values in PowerShell are wacky and contain all of the output produced during the function call.
# Because of this, we need a reliable way to communicate _only_ the result of executing a single command, not its
# output.  To accomplish this the value `$operationExitCode` is introduced and explicitly tracked.  The value
# cannot be directly set, however, because it would be scoped locally to the function, so the `script:` prefix
# is added when setting the value.
$operationExitCode = 0

function Get-Files {
    Write-Host "Job: $($job | ConvertTo-Json)"
    & $updaterTool clone `
        --job-path $env:DEPENDABOT_JOB_PATH `
        --repo-contents-path $env:DEPENDABOT_REPO_CONTENTS_PATH `
        --api-url $env:DEPENDABOT_API_URL `
        --job-id $env:DEPENDABOT_JOB_ID
    $script:operationExitCode = $LASTEXITCODE
}

function Install-Sdks {
    $installedSdks = dotnet --list-sdks | ForEach-Object { $_.Split(' ')[0] }
    if ($installedSdks.GetType().Name -eq "String") {
        # if only a single value was returned (expected in the container), then force it to an array
        $installedSdks = @($installedSdks)
    }
    Write-Host "Currently installed SDKs: $installedSdks"
    $rootDir = Convert-Path $env:DEPENDABOT_REPO_CONTENTS_PATH

    $candidateDirectories = @()
    if ("directory" -in $job.source.PSobject.Properties.Name) {
        $candidateDirectories += $job.source.directory
    }
    if ("directories" -in $job.source.PSobject.Properties.Name) {
        $candidateDirectories += $job.source.directories
    }

    $globalJsonRelativePaths = Get-DirectoriesForSdkInstall `
        -repoRoot $rootDir `
        -updateDirectories $candidateDirectories

    foreach ($globalJsonRelativePath in $globalJsonRelativePaths) {
        $globalJsonPath = "$rootDir/$globalJsonRelativePath"
        $globalJson = Get-Content $globalJsonPath | ConvertFrom-Json
        $sdkVersion = $globalJson.sdk.version
        if (-Not ($sdkVersion -in $installedSdks)) {
            $installedSdks += $sdkVersion
            Write-Host "Installing SDK $sdkVersion as specified in $globalJsonRelativePath"
            & $env:DOTNET_INSTALL_SCRIPT_PATH --version $sdkVersion --install-dir $env:DOTNET_INSTALL_DIR
        }
    }

    # report the final set
    dotnet --list-sdks
}

function Update-Files {
    # install relevant SDKs
    Install-Sdks
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
