using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class PackagesConfigUpdaterTests : TestBase
{
    [Theory]
    [MemberData(nameof(PackagesDirectoryPathTestData))]
    public void PathToPackagesDirectoryCanBeDetermined(string projectContents, string dependencyName, string dependencyVersion, string expectedPackagesDirectoryPath)
    {
        var projectBuildFile = ProjectBuildFile.Parse("/", "project.csproj", projectContents);
        var actualPackagesDirectorypath = PackagesConfigUpdater.GetPathToPackagesDirectory(projectBuildFile, dependencyName, dependencyVersion, "packages.config");
        Assert.Equal(expectedPackagesDirectoryPath, actualPackagesDirectorypath);
    }

    public static IEnumerable<object[]> PackagesDirectoryPathTestData()
    {
        // project with namespace
        yield return
        [
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
            "Newtonsoft.Json",
            "7.0.1",
            "../packages"
        ];

        // project without namespace
        yield return
        [
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
            "Newtonsoft.Json",
            "7.0.1",
            "../packages"
        ];

        // project with non-standard packages path
        yield return
        [
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
            "Newtonsoft.Json",
            "7.0.1",
            "../not-a-path-you-would-expect"
        ];
    }
}
