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

function Test-GlobalJsonDiscovery([string]$testDirectory, [string[]]$directories, [string[]]$expectedPaths) {
    Write-Host "Test-GlobalJsonDiscovery in $testDirectory ... " -NoNewline
    $testDirectoryFull = "$PSScriptRoot/test-data/$testDirectory"
    $actualPaths = Get-DirectoriesForSdkInstall -repoRoot $testDirectoryFull -updateDirectories $directories
    Assert-ArraysEqual -expected $expectedPaths -actual $actualPaths
    Write-Host "OK"
}

try {
    # verify SDK updater directories
    Test-GlobalJsonDiscovery `
        -testDirectory "global-json-discovery-root-no-file" `
        -directories @("/") `
        -expectedPaths @()

    Test-GlobalJsonDiscovery `
        -testDirectory "global-json-discovery-root-with-file" `
        -directories @("/") `
        -expectedPaths @("global.json")

    Test-GlobalJsonDiscovery `
        -testDirectory "global-json-discovery-none" `
        -directories @("src") `
        -expectedPaths @()

    Test-GlobalJsonDiscovery `
        -testDirectory "global-json-discovery-2-values" `
        -directories @("src") `
        -expectedPaths @("src/global.json", "global.json")
}
catch {
    Write-Host $_
    Write-Host $_.Exception
    Write-Host $_.ScriptStackTrace
    exit 1
}
