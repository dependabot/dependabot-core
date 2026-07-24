@{
    RootModule    = 'MyModule.psm1'
    ModuleVersion = '1.0.0'
    GUID          = '55555555-5555-5555-5555-555555555555'
    Author        = 'Example Author'

    RequiredModules = @(
        'Az.Accounts', # main module
        @{ModuleName = 'Az.Storage'; ModuleVersion = '1.0.0'} # storage module
    )
}
