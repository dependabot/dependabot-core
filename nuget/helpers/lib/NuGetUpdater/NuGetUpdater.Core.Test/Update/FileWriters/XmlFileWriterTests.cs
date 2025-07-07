using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class XmlFileWriterTests : FileWriterTestsBase
{
    public override IFileWriter FileWriter => new XmlFileWriter(new TestLogger());

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                ImportedFiles = [],
                AdditionalFiles = [],
            },
            requiredDependencies: [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_ElementDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>1.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                ImportedFiles = [],
                AdditionalFiles = [],
            },
            requiredDependencies: [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>2.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_AttributeDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                ImportedFiles = ["Directory.Packages.props"],
                AdditionalFiles = [],
            },
            requiredDependencies: [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="2.0.0" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_ElementDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency">
                          <Version>1.0.0</Version>
                        </PackageVersion>
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                ImportedFiles = ["Directory.Packages.props"],
                AdditionalFiles = [],
            },
            requiredDependencies: [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency">
                          <Version>2.0.0</Version>
                        </PackageVersion>
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeVariableUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <UnrelatedProperty>1.0.0</UnrelatedProperty>
                        <SomeDependencyVersion>$(UnrelatedProperty)</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                ImportedFiles = [],
                AdditionalFiles = [],
            },
            requiredDependencies: [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <UnrelatedProperty>2.0.0</UnrelatedProperty>
                        <SomeDependencyVersion>$(UnrelatedProperty)</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_MultiplePropertiesBestFitIsUsed()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_1)' == 'true'">4.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_2)' == 'true'">5.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                ImportedFiles = [],
                AdditionalFiles = [],
            },
            requiredDependencies: [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_1)' == 'true'">4.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_2)' == 'true'">5.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_TransitiveIsPinnedAtFront()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [
                    new Dependency("A.Transitive.Dependency", "2.0.0", DependencyType.PackageReference, IsTransitive: true),
                    new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                ],
                ImportedFiles = [],
                AdditionalFiles = [],
            },
            requiredDependencies: [
                new Dependency("A.Transitive.Dependency", "3.0.0", DependencyType.PackageReference),
                new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Transitive.Dependency" Version="3.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_TransitiveIsPinnedInMiddle()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [
                    new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                    new Dependency("Transitive.Dependency", "2.0.0", DependencyType.PackageReference, IsTransitive: true),
                ],
                ImportedFiles = [],
                AdditionalFiles = [],
            },
            requiredDependencies: [
                new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                new Dependency("Transitive.Dependency", "3.0.0", DependencyType.PackageReference),
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_ExistingPackageVersionElement_AlreadyCorrect()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [
                    new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                    new Dependency("Transitive.Dependency", "2.0.0", DependencyType.PackageReference, IsTransitive: true),
                ],
                ImportedFiles = ["Directory.Packages.props"],
                AdditionalFiles = [],
            },
            requiredDependencies: [
                new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                new Dependency("Transitive.Dependency", "3.0.0", DependencyType.PackageReference),
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_ExistingPackageVersionElement_VersionOverrideNeeded()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="9.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [
                    new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                    new Dependency("Transitive.Dependency", "2.0.0", DependencyType.PackageReference, IsTransitive: true),
                ],
                ImportedFiles = ["Directory.Packages.props"],
                AdditionalFiles = [],
            },
            requiredDependencies: [
                new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                new Dependency("Transitive.Dependency", "3.0.0", DependencyType.PackageReference),
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" VersionOverride="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="9.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_NoExistingPackageVersionElement_VersionElementAddedAtFront()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [
                    new Dependency("A.Transitive.Dependency", "2.0.0", DependencyType.PackageReference, IsTransitive: true),
                    new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                ],
                ImportedFiles = ["Directory.Packages.props"],
                AdditionalFiles = [],
            },
            requiredDependencies: [
                new Dependency("A.Transitive.Dependency", "3.0.0", DependencyType.PackageReference),
                new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Transitive.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="A.Transitive.Dependency" Version="3.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_NoExistingPackageVersionElement_VersionElementAddedInMiddle()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [
                    new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                    new Dependency("Transitive.Dependency", "2.0.0", DependencyType.PackageReference, IsTransitive: true),
                ],
                ImportedFiles = ["Directory.Packages.props"],
                AdditionalFiles = [],
            },
            requiredDependencies: [
                new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
                new Dependency("Transitive.Dependency", "3.0.0", DependencyType.PackageReference),
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }
}
