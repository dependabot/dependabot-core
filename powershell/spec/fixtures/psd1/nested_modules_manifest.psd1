@{
    RootModule = 'NestedRoot.psm1'
    ModuleVersion = '1.0.0'
    GUID = '77ef0f4b-c6a7-4f1d-98ca-3890f7dd73a3'

    NestedModules = @(
        @{ ModuleName = 'Pester'; RequiredVersion = '5.0.0' }
        @{ ModuleName = 'PSScriptAnalyzer'; ModuleVersion = '1.21.0' }
        './LocalNested.psm1'
        'LocalNested.psm1'
        'LocalNested.dll'
    )
}
