@{
    RootModule        = 'MyModule.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '11111111-1111-1111-1111-111111111111'
    Author            = 'Example Author'

    RequiredModules = @(
        'Az.Accounts',
        @{ ModuleName = 'Az.Storage'; ModuleVersion = '1.0.0' },
        @{
            ModuleName     = 'Az.Compute'
            RequiredVersion = '2.3.4'
            GUID           = '22222222-2222-2222-2222-222222222222'
        },
        @{ ModuleName = 'Az.Network'; ModuleVersion = '1.0.0'; MaximumVersion = '2.0.0' },
        '.\Modules\LocalModule.psd1',
        @{ ModuleName = 'Az.Invalid'; ModuleVersion = '1.0.0'; RequiredVersion = '2.0.0' }
    )
}
