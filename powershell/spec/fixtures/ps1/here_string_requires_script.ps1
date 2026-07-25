#Requires -Modules @{ModuleName = 'Az.Real'; ModuleVersion = '1.0.0'}

$exampleUsage = @"
#Requires -Modules FakeModule.FromHereString
"@

param(
    [string]$ResourceGroup
)

Write-Host "Deploying to $ResourceGroup"
