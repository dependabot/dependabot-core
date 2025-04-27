Set-StrictMode -version 2.0
$ErrorActionPreference = "Stop"

. $PSScriptRoot\common.ps1

function Assert-ArraysEqual([string[]]$expected, [string[]]$actual) {
    $expectedText = $expected -join ", "
    $actualText = $actual -join ", "
    if ($expectedText -ne $actualText) {
        throw "Expected array values '$expectedText' but was '$actualText'"
    }
}

function Test-GlobalJsonVersions([string] $testDirectory, [string[]] $directories, [string[]] $installedSdks, [string[]] $expectedSdksToInstall) {
    Write-Host "Test-GlobalJsonVersions in $testDirectory ... " -NoNewline
    $testDirectoryFull = "$PSScriptRoot/test-data/$testDirectory"
    $actualSdksToInstall = Get-SdkVersionsToInstall -repoRoot $testDirectoryFull -updateDirectories $directories -installedSdks $installedSdks
    Assert-ArraysEqual -expected $expectedSdksToInstall -actual $actualSdksToInstall
    Write-Host "OK"
}

function Test-RequiredTargetingPacks([string] $testDirectory, [string[]] $expectedTargetingPacks) {
    Write-Host "Test-RequiredTargetingPacks in $testDirectory ... " -NoNewLine
    $testDirectoryFull = "$PSScriptRoot/test-data/$testDirectory"
    $actualTargetingPacks = Get-RequiredTargetingPacks -sdkInstallDir $testDirectoryFull
    Assert-ArraysEqual -expected $expectedTargetingPacks -actual $actualTargetingPacks
    Write-Host "OK"
}

function Test-NuGetConfig([string]$scenarioName, [string]$jobString, [string[]]$expectedLines) {
    Write-Host "Test-NuGetConfig $scenarioName ... " -NoNewLine
    $job = ConvertFrom-Json -InputObject $jobString
    $actualLines = Get-NuGetConfigContents -creds $job.'credentials-metadata'
    Assert-ArraysEqual -expected $expectedLines -actual $actualLines
    Write-Host "OK"
}

try {
    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-root-no-file" `
        -directories @("/") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @()

    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-root-with-file" `
        -directories @("/") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @("1.2.3")

    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-none" `
        -directories @("src") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @()

    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-2-values" `
        -directories @("src") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @("1.2.3", "4.5.6")

    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-empty-object" `
        -directories @("/src") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @("1.2.3")

    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-recursive-wildcard" `
        -directories @("/**") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @("1.2.3")

    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-recursive-wildcard" `
        -directories @("/src/**/*") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @()

    Test-GlobalJsonVersions `
        -testDirectory "global-json-discovery-none" `
        -directories @("/dir-that-does-not-exist") `
        -installedSdks @("8.0.404", "9.0.101") `
        -expectedSdksToInstall @()

    Test-RequiredTargetingPacks `
        -testDirectory "targeting-packs" `
        -expectedTargetingPacks @("Some.Targeting.Pack.Ref/1.0.1", "Some.Other.Targeting.Pack.Ref/1.0.2", "Some.Targeting.Pack.Ref/4.0.1", "Some.Other.Targeting.Pack.Ref/4.0.2")

    Test-NuGetConfig `
        -scenarioName "empty-set" `
        -jobString @"
{
  "credentials-metadata": []
}
"@ `
        -creds @() `
        -expectedLines @(
            '<?xml version="1.0" encoding="utf-8"?>'
            '<configuration>',
            '  <packageSources>',
            '    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />',
            '  </packageSources>',
            '</configuration>'
        )

    Test-NuGetConfig `
        -scenarioName "only-nuget-feeds-added" `
        -jobString @"
{
  "credentials-metadata": [
    {"type":"nuget_feed", "url":"https://nuget.example.com/1/index.json"},
    {"type":"npm_feed", "url":"https://npm.example.com", "replaces-base":true},
    {"type":"nuget_feed", "url":"https://nuget.example.com/2/index.json"}
  ]
}
"@ `
        -expectedLines @(
            '<?xml version="1.0" encoding="utf-8"?>'
            '<configuration>',
            '  <packageSources>',
            '    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />',
            '    <add key="nuget_source_1" value="https://nuget.example.com/1/index.json" />',
            '    <add key="nuget_source_2" value="https://nuget.example.com/2/index.json" />',
            '  </packageSources>',
            '</configuration>'
        )

    Test-NuGetConfig `
        -scenarioName "replaces-base" `
        -jobString @"
{
  "credentials-metadata": [
    {"type":"nuget_feed", "url":"https://nuget.example.com/1/index.json"},
    {"type":"npm_feed", "url":"https://npm.example.com"},
    {"type":"nuget_feed", "url":"https://nuget.example.com/2/index.json","replaces-base":true}
  ]
}
"@ `
        -expectedLines @(
            '<?xml version="1.0" encoding="utf-8"?>'
            '<configuration>',
            '  <packageSources>',
            '    <add key="nuget_source_1" value="https://nuget.example.com/1/index.json" />',
            '    <add key="nuget_source_2" value="https://nuget.example.com/2/index.json" />',
            '  </packageSources>',
            '</configuration>'
        )
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
