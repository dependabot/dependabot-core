function Write-LogMessage([string] $message, [switch] $NoNewLine) {
    if ("$env:DEPENDABOT_LOG_MESSAGES" -ne "true") {
        return
    }
    if ($NoNewLine) {
        Write-Host $message -NoNewline
    }
    else {
        Write-Host $message
    }
}

function Get-SdkVersionsToInstall([string] $repoRoot, [string[]] $installedSdks) {
    $sdksToInstall = @()
    $globalJsonPaths = Get-GlobalJsonForSdkInstall -repoRoot $repoRoot
    Write-LogMessage "Discovered global.json files: $globalJsonPaths"
    foreach ($globalJsonPath in $globalJsonPaths) {
        $resolvedGlobalJsonPath = Convert-Path "$repoRoot/$globalJsonPath"
        Write-LogMessage "  Processing $globalJsonPath (resolved to $resolvedGlobalJsonPath) for SDK version information"
        $globalJson = Get-Content $resolvedGlobalJsonPath -Raw | ConvertFrom-Json
        if (@($globalJson.PSobject.Properties).Count -eq 0) {
            Write-LogMessage "    No properties found in $globalJsonPath, skipping"
            continue
        }
        if ("sdk" -notin $globalJson.PSobject.Properties.Name) {
            Write-LogMessage "    No 'sdk' property found in $globalJsonPath, skipping"
            continue
        }
        if ("version" -notin $globalJson.sdk.PSobject.Properties.Name) {
            Write-LogMessage "    No 'sdk.version' property found in $globalJsonPath, skipping"
            continue
        }

        $sdkVersion = $globalJson.sdk.version
        if ($null -ne $sdkVersion) {
            $versionParts = $sdkVersion.Split(".")
            if (($versionParts.Length -eq 3) -and ($versionParts[2].Length -eq 1) -and ($null -eq ($versionParts[2] -as [int]))) {
                # non-integer single character third part, e.g. 9.0.x => report 9.0 for channel install
                $unmodifiedSdkVersion = $sdkVersion
                $sdkVersion = "$($versionParts[0]).$($versionParts[1])"
                Write-LogMessage "    SDK version '$unmodifiedSdkVersion' auto-corrected to '$sdkVersion'"
            }
        }
        if (($null -ne $sdkVersion) -and
            (-not ($sdkVersion -in $sdksToInstall)) -and
            (-not ($sdkVersion -in $installedSdks)))
        {
            Write-LogMessage "    SDK version '$sdkVersion' added to install list"
            $installedSdks += $sdkVersion
            $sdksToInstall += $sdkVersion
        }
    }

    return ,$sdksToInstall
}

function Get-GlobalJsonForSdkInstall([string] $repoRoot) {
    $repoRoot = Convert-Path $repoRoot
    Write-LogMessage "Discovering global.json files for SDK install under repo root '$repoRoot'"
    $resolvedGlobalJsonPaths = @()
    $directoriesToSearch = [System.Collections.Generic.Queue[string]]::new()
    $directoriesToSearch.Enqueue($repoRoot)
    while ($directoriesToSearch.Count -gt 0) {
        $directory = $directoriesToSearch.Dequeue()
        $globalJsonPath = Join-Path $directory "global.json"
        if (Test-Path -LiteralPath $globalJsonPath -PathType Leaf) {
            $resolvedGlobalJsonPaths += [System.IO.Path]::GetRelativePath($repoRoot, $globalJsonPath).Replace("\", "/")
        }

        $childDirectories = Get-ChildItem -LiteralPath $directory -Directory -Force |
            Where-Object {
                $_.Name -ne ".git" -and
                -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
            }
        foreach ($childDirectory in $childDirectories) {
            $directoriesToSearch.Enqueue($childDirectory.FullName)
        }
    }

    return ,($resolvedGlobalJsonPaths | Sort-Object)
}

function Get-Job([string]$jobFilePath) {
    $jobString = Get-Content -Path $jobFilePath
    $job = (ConvertFrom-Json -InputObject $jobString).job
    return $job
}

function Install-Sdks([string]$repoContentsPath, [string]$dotnetInstallScriptPath, [string]$dotnetInstallDir) {
    $installedSdks = dotnet --list-sdks | ForEach-Object { $_.Split(' ')[0] }
    if ($installedSdks.GetType().Name -eq "String") {
        # if only a single value was returned (expected in the container), then force it to an array
        $installedSdks = @($installedSdks)
    }
    Write-LogMessage "Currently installed SDKs: $installedSdks"
    $rootDir = Convert-Path $repoContentsPath

    $sdksToInstall = Get-SdkVersionsToInstall -repoRoot $rootDir -installedSdks $installedSdks
    foreach ($sdkVersion in $sdksToInstall) {
        $versionParts = $sdkVersion.Split(".")
        if (($versionParts.Length -eq 2) -or ($versionParts.Length -eq 3 -and $versionParts[2] -eq "0")) {
            $channelVersion = "$($versionParts[0]).$($versionParts[1])"
            Write-LogMessage "Installing SDK from channel $channelVersion"
            & $dotnetInstallScriptPath --channel $channelVersion --install-dir $dotnetInstallDir
        }
        else {
            Write-LogMessage "Installing SDK $sdkVersion"
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
            if (Test-Path -LiteralPath $requiredTargetingPackDirectory -PathType Container) {
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
        Write-LogMessage "Downloading targeting pack [$packName/$packVersion]"
        Invoke-WebRequest -Uri $targetingPackUrl -OutFile $archiveName
        Write-LogMessage "Extracting targeting pack [$packName/$packVersion] to $destinationDirectory"
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
            Write-LogMessage "Renaming '$file' to '$newName'"
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

        if ("url" -notin $cred.PSObject.Properties.Name -or [string]::IsNullOrWhiteSpace([string]$cred.url)) {
            continue
        }

        $sourceName = "nuget_source_$i"
        $i++
        $url = $cred.url
        $insecureAttr = ""
        if ($url.StartsWith("http://")) {
            $insecureAttr = "allowInsecureConnections=`"true`" "
        }

        $customSourceLines += "    <add key=`"$sourceName`" value=`"$url`" $insecureAttr/>"
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
    Write-LogMessage "User-level NuGet.Config set to ..."
    Get-Content -Path $nugetConfigPath
}
