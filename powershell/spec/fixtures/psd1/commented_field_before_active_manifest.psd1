@{
    RootModule    = 'MyModule.psm1'
    ModuleVersion = '1.0.0'
    GUID          = '66666666-6666-6666-6666-666666666666'
    Author        = 'Example Author'

    RequiredModules = @(
        @{ModuleName = 'Az.Sql'; # RequiredVersion = '1.0.0'
          RequiredVersion = '1.0.0'}
    )
}
