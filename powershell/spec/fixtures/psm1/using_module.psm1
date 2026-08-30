using module @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0'; MaximumVersion = '5.99.99' }
using module Microsoft.PowerShell.Management

function Get-UsingModuleContract {
    return 'Using module contract'
}
