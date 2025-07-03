using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class XmlFileWriterTests : FileWriterTestsBase
{
    public override IFileWriter FileWriter => new XmlFileWriter();

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
}
