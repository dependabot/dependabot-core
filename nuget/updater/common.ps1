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
