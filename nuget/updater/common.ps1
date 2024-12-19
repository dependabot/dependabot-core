# Walk from each update directory to the root reporting all global.json files.
function Get-DirectoriesForSdkInstall([string] $repoRoot, [string[]]$updateDirectories) {
    $repoRoot = Convert-Path $repoRoot
    $repoRootParent = Split-Path -Parent $repoRoot
    $globalJsonPaths = @()
    foreach ($updateDirectory in $updateDirectories) {
        $candidateDir = Convert-Path "$repoRoot/$updateDirectory"
        if (Test-Path $candidateDir) {
            while ($true) {
                $globalJsonPath = Join-Path $candidateDir "global.json"
                if (Test-Path $globalJsonPath) {
                    $repoRelativeGlobalJsonPath = [System.IO.Path]::GetRelativePath($repoRoot, $globalJsonPath).Replace("\", "/")
                    $globalJsonPaths += $repoRelativeGlobalJsonPath
                }

                $candidateDir = Split-Path -Parent $candidateDir
                if ($null -eq $candidateDir -or `
                    $candidateDir -eq $repoRootParent) {
                    break
                }
            }
        }
    }

    return ,$globalJsonPaths
}

function Get-Job([string]$jobFilePath) {
    $jobString = Get-Content -Path $jobFilePath
    $job = (ConvertFrom-Json -InputObject $jobString).job
    return $job
}

function Install-Sdks([string]$jobFilePath, [string]$repoContentsPath, [string]$dotnetInstallScriptPath, [string]$dotnetInstallDir) {
    $job = Get-Job -jobFilePath $jobFilePath

    $installedSdks = dotnet --list-sdks | ForEach-Object { $_.Split(' ')[0] }
    if ($installedSdks.GetType().Name -eq "String") {
        # if only a single value was returned (expected in the container), then force it to an array
        $installedSdks = @($installedSdks)
    }
    Write-Host "Currently installed SDKs: $installedSdks"
    $rootDir = Convert-Path $repoContentsPath

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
            & $dotnetInstallScriptPath --version $sdkVersion --install-dir $dotnetInstallDir
        }
    }

    # report the final set
    dotnet --list-sdks
}
