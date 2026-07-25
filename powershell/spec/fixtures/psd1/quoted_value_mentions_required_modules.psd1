@{
    RootModule    = 'MyModule.psm1'
    ModuleVersion = '1.0.0'
    GUID          = '55555555-5555-5555-5555-555555555555'
    Author        = 'Example Author'
    Description   = 'See RequiredModules = @(''Fake'') for an example of the old syntax.'
    NotRequiredModules = @('Fake')

    RequiredModules = @(
        @{ModuleName = 'Az.Real'; ModuleVersion = '1.0.0'}
    )
}
