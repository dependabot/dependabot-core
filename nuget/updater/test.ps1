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
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
