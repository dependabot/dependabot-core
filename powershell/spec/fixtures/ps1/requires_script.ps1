#Requires -Modules Az.Accounts
#Requires -Modules @{ModuleName = 'Az.Storage'; ModuleVersion = '1.0.0'}
#Requires -Modules Az.Compute, @{ModuleName = 'Az.Network'; RequiredVersion = '2.3.4'}

param(
    [string]$ResourceGroup
)

Write-Host "Deploying to $ResourceGroup"
