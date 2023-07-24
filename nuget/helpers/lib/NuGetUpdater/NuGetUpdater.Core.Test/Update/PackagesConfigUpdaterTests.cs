using System.Collections.Generic;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class PackagesConfigUpdaterTests
{
    public PackagesConfigUpdaterTests()
    {
        MSBuildHelper.RegisterMSBuild();
    }

    [Theory]
    [InlineData( // no change made
        @"<Project><ItemGroup><Reference><HintPath>path\to\file.dll</HintPath></Reference></ItemGroup></Project>",
        @"<Project><ItemGroup><Reference><HintPath>path\to\file.dll</HintPath></Reference></ItemGroup></Project>"
    )]
    [InlineData( // change from `/` to `\`
        "<Project><ItemGroup><Reference><HintPath>path/to/file.dll</HintPath></Reference></ItemGroup></Project>",
        @"<Project><ItemGroup><Reference><HintPath>path\to\file.dll</HintPath></Reference></ItemGroup></Project>"
    )]
    [InlineData( // multiple changes made
        "<Project><ItemGroup><Reference><HintPath>path1/to1/file1.dll</HintPath></Reference><Reference><HintPath>path2/to2/file2.dll</HintPath></Reference></ItemGroup></Project>",
        @"<Project><ItemGroup><Reference><HintPath>path1\to1\file1.dll</HintPath></Reference><Reference><HintPath>path2\to2\file2.dll</HintPath></Reference></ItemGroup></Project>"
    )]
    public void ReferenceHintPathsCanBeNormalized(string originalXml, string expectedXml)
    {
        var actualXml = PackagesConfigUpdater.NormalizeDirectorySeparatorsInProject(originalXml);
        Assert.Equal(expectedXml, actualXml);
    }

    [Theory]
    [MemberData(nameof(PackagesDirectoryPathTestData))]
    public void PathToPackagesDirectoryCanBeDetermined(string projectContents, string dependencyName, string dependencyVersion, string expectedPackagesDirectoryPath)
    {
        var actualPackagesDirectorypath = PackagesConfigUpdater.GetPathToPackagesDirectory(projectContents, dependencyName, dependencyVersion);
        Assert.Equal(expectedPackagesDirectoryPath, actualPackagesDirectorypath);
    }

    public static IEnumerable<object[]> PackagesDirectoryPathTestData()
    {
        // project with namespace
        yield return new object[]
        {
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
            @"..\packages"
        };

        // project without namespace
        yield return new object[]
        {
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
            @"..\packages"
        };

        // project with non-standard packages path
        yield return new object[]
        {
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
            @"..\not-a-path-you-would-expect"
        };
    }
}