using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class PackagesConfigUpdaterTests : TestBase
{
    [Theory]
    [MemberData(nameof(PackagesDirectoryPathTestData))]
    public async Task PathToPackagesDirectoryCanBeDetermined(string projectContents, string? packagesConfigContents, string dependencyName, string dependencyVersion, string expectedPackagesDirectoryPath)
    {
        using var tempDir = new TemporaryDirectory();
        string? packagesConfigPath = null;
        if (packagesConfigContents is not null)
        {
            packagesConfigPath = Path.Join(tempDir.DirectoryPath, "packages.config");
            await File.WriteAllTextAsync(packagesConfigPath, packagesConfigContents);
        }

        var projectBuildFile = ProjectBuildFile.Parse("/", "project.csproj", projectContents);
        var actualPackagesDirectorypath = PackagesConfigUpdater.GetPathToPackagesDirectory(projectBuildFile, dependencyName, dependencyVersion, packagesConfigPath);
        Assert.Equal(expectedPackagesDirectoryPath, actualPackagesDirectorypath);
    }

    public static IEnumerable<object?[]> PackagesDirectoryPathTestData()
    {
        // project with namespace
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            null,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../packages"
        ];

        // project without namespace
        yield return
        [
            // project contents
            """
            <Project>
              <ItemGroup>
                <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            null,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../packages"
        ];

        // project with non-standard packages path
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\not-a-path-you-would-expect\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            null,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../not-a-path-you-would-expect"
        ];

        // project without expected packages path, but has others
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Some.Other.Package, Version=1.2.3.4, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\..\..\packages\Some.Other.Package.1.2.3\lib\net45\Some.Other.Package.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            """
            <packages>
              <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
            </packages>
            """,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../../../packages"
        ];

        // project without expected package, but exists in packages.config, default is returned
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            """
            <packages>
              <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
            </packages>
            """,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../packages"
        ];

        // project without expected package and not in packages.config
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            """
            <packages>
            </packages>
            """,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            null
        ];
    }
}
