function Get-SdkVersionsToInstall([string] $repoRoot, [string[]] $updateDirectories, [string[]] $installedSdks) {
    $sdksToInstall = @()
    $globalJsonPaths = Get-GlobalJsonForSdkInstall -repoRoot $repoRoot -updateDirectories $updateDirectories
    foreach ($globalJsonPath in $globalJsonPaths) {
        $resolvedGlobalJsonPath = Convert-Path "$repoRoot/$globalJsonPath"
        $globalJson = Get-Content $resolvedGlobalJsonPath | ConvertFrom-Json
        if (@($globalJson.PSobject.Properties).Count -eq 0) {
            continue
        }
        if ("sdk" -notin $globalJson.PSobject.Properties.Name) {
            continue
        }
        if ("version" -notin $globalJson.sdk.PSobject.Properties.Name) {
            continue
        }

        $sdkVersion = $globalJson.sdk.version
        if (($null -ne $sdkVersion) -and (-not ($sdkVersion -in $installedSdks)) -and (-not ($sdkVersion -in $installedSdks))) {
            $installedSdks += $sdkVersion
            $sdksToInstall += $sdkVersion
        }
    }

    return ,$sdksToInstall
}

# Walk from each update directory to the root reporting all global.json files.
function Get-GlobalJsonForSdkInstall([string] $repoRoot, [string[]] $updateDirectories) {
    $repoRoot = Convert-Path $repoRoot
    $repoRootParent = Split-Path -Parent $repoRoot
    $globalJsonPaths = @()
    foreach ($updateDirectory in $updateDirectories) {
        if (-not (Test-Path "$repoRoot/$updateDirectory")) {
            # directory doesn't exist
            continue
        }

        # $updateDirectory might be a recursive wildcard like "/**"; this takes care of that
        $candidateDirs = Convert-Path "$repoRoot/$updateDirectory"
        foreach ($candidateDir in $candidateDirs) {
            if (Test-Path $candidateDir -PathType Container) {
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

    $sdksToInstall = Get-SdkVersionsToInstall -repoRoot $rootDir -updateDirectories $candidateDirectories -installedSdks $installedSdks
    foreach ($sdkVersion in $sdksToInstall) {
        $versionParts = $sdkVersion.Split(".")
        if ($versionParts.Length -eq 3 -and $versionParts[2] -eq "0") {
            $channelVersion = "$($versionParts[0]).$($versionParts[1])"
            Write-Host "Installing SDK from channel $channelVersion"
            & $dotnetInstallScriptPath --channel $channelVersion --install-dir $dotnetInstallDir
        }
        else {
            Write-Host "Installing SDK $sdkVersion"
            & $dotnetInstallScriptPath --version $sdkVersion --install-dir $dotnetInstallDir
        }
    }

    # report the final set
    dotnet --list-sdks
}

function Get-RequiredTargetingPacks([string]$sdkInstallDir) {
    $targetingPacksToInstall = @()
    $sdkDirs = Get-ChildItem -Path "$sdkInstallDir/sdk" -Directory
    foreach ($sdkDir in $sdkDirs) {
        $versionsPropsFile = "$sdkDir/Microsoft.NETCoreSdk.BundledVersions.props"
        $knownFrameworkReferences = Select-Xml -Path $versionsPropsFile -XPath "/Project/ItemGroup/KnownFrameworkReference"
        foreach ($frameworkRef in $knownFrameworkReferences) {
            $targetingPackName = $frameworkRef.Node.TargetingPackName
            $targetingPackVersion = $frameworkRef.Node.TargetingPackVersion
            $requiredTargetingPackName = "$targetingPackName/$targetingPackVersion"
            $requiredTargetingPackDirectory = Join-Path $sdkInstallDir "packs/$requiredTargetingPackName"
            if (Test-Path -Path $requiredTargetingPackDirectory) {
                continue
            }

            if (-not ($requiredTargetingPackName -in $targetingPacksToInstall)) {
                $targetingPacksToInstall += $requiredTargetingPackName
            }
        }
    }

    return ,$targetingPacksToInstall
}

function Install-TargetingPacks([string]$sdkInstallDir, [string[]]$targetingPacks) {
    foreach ($targetingPack in $targetingPacks) {
        $parts = $targetingPack -Split "/"
        $packName = $parts[0]
        $packVersion = $parts[1]
        $targetingPackUrl = "https://www.nuget.org/api/v2/package/$packName/$packVersion"
        $destinationDirectory = "$sdkInstallDir/packs/$packName/$packVersion"
        $archiveName = "$destinationDirectory/$packName.$packVersion.zip"
        New-Item $destinationDirectory -ItemType Directory -Force | Out-Null
        Write-Host "Downloading targeting pack [$packName/$packVersion]"
        Invoke-WebRequest -Uri $targetingPackUrl -OutFile $archiveName
        Write-Host "Extracting targeting pack [$packName/$packVersion] to $destinationDirectory"
        Expand-Archive -Path $archiveName -DestinationPath $destinationDirectory -Force
        Remove-Item -Path $archiveName
    }
}

function Repair-FileCasingForName([string]$fileName) {
    # Get-ChildItem is case-insensitive
    $discoveredFiles = Get-ChildItem $env:DEPENDABOT_REPO_CONTENTS_PATH -r -inc $fileName
    foreach ($file in $discoveredFiles) {
        # `-cne` = Case-sensitive Not Equal
        if ($file.Name -cne $fileName) {
            $newName = "$($file.Directory)/$fileName"
            Write-Host "Renaming '$file' to '$newName'"
            Rename-Item -Path $file -NewName $newName
        }
    }
}

function Repair-FileCasing() {
    Repair-FileCasingForName -fileName "NuGet.Config"
}

function Get-NuGetConfigContents([PSObject[]]$creds) {
    $baseSourceLines = @("    <add key=`"nuget.org`" value=`"https://api.nuget.org/v3/index.json`" />")
    $customSourceLines = @()
    $i = 1
    foreach ($cred in $creds) {
        if ($cred.type -ne "nuget_feed") {
            continue
        }

        if ("replaces-base" -in $cred.PSObject.Properties.Name -And $cred.'replaces-base') {
            $baseSourceLines = @()
        }

        $sourceName = "nuget_source_$i"
        $i++
        $url = $cred.url
        $customSourceLines += "    <add key=`"$sourceName`" value=`"$url`" />"
    }

    $lines = @()
    $lines += '<?xml version="1.0" encoding="utf-8"?>'
    $lines += '<configuration>'
    $lines += '  <packageSources>'
    $lines = $($lines; $baseSourceLines; $customSourceLines)
    $lines += '  </packageSources>'
    $lines += '</configuration>'
    return ,$lines
}

function Set-NuGetConfig() {
    $job = Get-Job -jobFilePath $env:DEPENDABOT_JOB_PATH
    $lines = Get-NuGetConfigContents -creds $job.'credentials-metadata'
    $nugetConfigPath = "$HOME/.nuget/NuGet/NuGet.Config"
    $lines | Set-Content -Path $nugetConfigPath -Encoding utf8
    Write-Host "User-level NuGet.Config set to ..."
    Get-Content -Path $nugetConfigPath
}
