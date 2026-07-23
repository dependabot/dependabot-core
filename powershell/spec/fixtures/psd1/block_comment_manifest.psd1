@{
    RootModule    = 'MyModule.psm1'
    ModuleVersion = '1.0.0'
    GUID          = '66666666-6666-6666-6666-666666666666'
    Author        = 'Example Author'

<#
    Example usage:
    RequiredModules = @('FakeModule')
#>

    RequiredModules = @(
        @{ModuleName = 'Az.Real'; ModuleVersion = '1.0.0'}
    )
}
