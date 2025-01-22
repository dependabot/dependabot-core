Set-StrictMode -version 2.0
$ErrorActionPreference = "Stop"

. $PSScriptRoot\common.ps1

function Assert-ArraysEqual([string[]]$expected, [string[]]$actual) {
    $expectedText = $expected -join ", "
    $actualText = $actual -join ", "
    if ($expected.Length -ne $actual.Length) {
        throw "Expected array length $($expected.Length) but was $($actual.Length).  Values: [$expectedText] vs [$actualText]"
    }
    for ($i = 0; $i -lt $expected.Length; $i++) {
        if ($expected[$i] -ne $actual[$i]) {
            throw "Expected array element at index $i to be '$($expected[$i])' but was '$($actual[$i])'"
        }
    }
}

function Test-GlobalJsonVersions([string] $testDirectory, [string[]] $directories, [string[]] $installedSdks, [string[]] $expectedSdksToInstall) {
    Write-Host "Test-GlobalJsonVersions in $testDirectory ... " -NoNewline
    $testDirectoryFull = "$PSScriptRoot/test-data/$testDirectory"
    $actualSdksToInstall = Get-SdkVersionsToInstall -repoRoot $testDirectoryFull -updateDirectories $directories -installedSdks $installedSdks
    Assert-ArraysEqual -expected $expectedSdksToInstall -actual $actualSdksToInstall
    Write-Host "OK"
}

try {
    # verify SDK updater directories
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
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
