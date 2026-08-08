#Requires -Modules @{ModuleName = 'Pester'; ModuleVersion = '5.0.0'; MaximumVersion = '5.99.99'}

function Invoke-Something {
    [CmdletBinding()]
    param()

    Write-Verbose "Doing something"
}

Export-ModuleMember -Function Invoke-Something
