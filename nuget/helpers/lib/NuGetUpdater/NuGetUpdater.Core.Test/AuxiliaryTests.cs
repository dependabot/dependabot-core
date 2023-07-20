using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

using NuGet;

using Xunit;

namespace NuGetUpdater.Core.Test;

public class AuxiliaryTests
{
    public AuxiliaryTests()
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
        var actualXml = PackageConfigUpdater.NormalizeDirectorySeparatorsInProject(originalXml);
        Assert.Equal(expectedXml, actualXml);
    }

    [Theory]
    [MemberData(nameof(SolutionProjectPathTestData))]
    public void ProjectPathsCanBeParsedFromSolutionFiles(string solutionContent, string[] expectedProjectSubPaths)
    {
        var solutionPath = Path.GetTempFileName();
        var solutionDirectory = Path.GetDirectoryName(solutionPath);
        try
        {
            File.WriteAllText(solutionPath, solutionContent);
            var actualProjectSubPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath);
            Assert.Equal(expectedProjectSubPaths.Select(path => Path.Combine(solutionDirectory, path)), actualProjectSubPaths);
        }
        finally
        {
            File.Delete(solutionPath);
        }
    }

    [Theory]
    [MemberData(nameof(PackagesDirectoryPathTestData))]
    public void PathToPackagesDirectoryCanBeDetermined(string projectContents, string dependencyName, string dependencyVersion, string expectedPackagesDirectoryPath)
    {
        var actualPackagesDirectorypath = PackageConfigUpdater.GetPathToPackagesDirectory(projectContents, dependencyName, dependencyVersion);
        Assert.Equal(expectedPackagesDirectoryPath, actualPackagesDirectorypath);
    }

    [Theory]
    [InlineData("<Project><PropertyGroup><TargetFramework>netstandard2.0</TargetFramework></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>netstandard2.0</TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>  ; netstandard2.0 ; </TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>netstandard2.0 ; netstandard2.1 ; </TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", "netstandard2.1")]
    public void TfmsCanBeDeterminedFromProjectContents(string projectContents, string? expectedTfm1, string? expectedTfm2)
    {
        var projectPath = Path.GetTempFileName();
        try
        {
            File.WriteAllText(projectPath, projectContents);
            var expectedTfms = new[] { expectedTfm1, expectedTfm2 }.Where(tfm => tfm is not null).ToArray();
            var actualTfms = MSBuildHelper.GetTargetFrameworkMonikersFromProject(projectPath);
            Assert.Equal(expectedTfms, actualTfms);
        }
        finally
        {
            File.Delete(projectPath);
        }
    }

    [Fact]
    public async Task AllPackageDependenciesCanBeTraversed()
    {
        using var temp = new TemporaryDirectory();
        var expectedDependencies = new[]
        {
            ("Microsoft.Bcl.AsyncInterfaces", "7.0.0"),
            ("Microsoft.Extensions.DependencyInjection", "7.0.0"),
            ("Microsoft.Extensions.DependencyInjection.Abstractions", "7.0.0"),
            ("Microsoft.Extensions.Http", "7.0.0"),
            ("Microsoft.Extensions.Logging", "7.0.0"),
            ("Microsoft.Extensions.Logging.Abstractions", "7.0.0"),
            ("Microsoft.Extensions.Options", "7.0.0"),
            ("Microsoft.Extensions.Primitives", "7.0.0"),
            ("System.Buffers", "4.5.1"),
            ("System.ComponentModel.Annotations", "5.0.0"),
            ("System.Diagnostics.DiagnosticSource", "7.0.0"),
            ("System.Memory", "4.5.5"),
            ("System.Numerics.Vectors", "4.4.0"),
            ("System.Runtime.CompilerServices.Unsafe", "6.0.0"),
            ("System.Threading.Tasks.Extensions", "4.5.4"),
        };
        var actualDependencies = await SdkPackageUpdater.GetAllPackageDependenciesAsync(temp.DirectoryPath, "netstandard2.0", new[] { (PackageName: "Microsoft.Extensions.Http", VersionString: "7.0.0") });
        Assert.Equal(expectedDependencies, actualDependencies);
    }

    public static IEnumerable<object[]> SolutionProjectPathTestData()
    {
        yield return new object[]
        {
            """
            Microsoft Visual Studio Solution File, Format Version 12.00
            # Visual Studio 14
            VisualStudioVersion = 14.0.22705.0
            MinimumVisualStudioVersion = 10.0.40219.1
            Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Some.Project", "src\Some.Project\SomeProject.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20C}"
            EndProject
            Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Some.Project.Test", "src\Some.Project.Test\Some.Project.Test.csproj", "{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}"
            EndProject
            Global
            	GlobalSection(SolutionConfigurationPlatforms) = preSolution
            		Debug|Any CPU = Debug|Any CPU
            		Release|Any CPU = Release|Any CPU
            	EndGlobalSection
            	GlobalSection(ProjectConfigurationPlatforms) = postSolution
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Debug|Any CPU.Build.0 = Debug|Any CPU
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Release|Any CPU.ActiveCfg = Release|Any CPU
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Release|Any CPU.Build.0 = Release|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Debug|Any CPU.Build.0 = Debug|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Release|Any CPU.ActiveCfg = Release|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Release|Any CPU.Build.0 = Release|Any CPU
            	EndGlobalSection
            	GlobalSection(SolutionProperties) = preSolution
            		HideSolutionNode = FALSE
            	EndGlobalSection
            EndGlobal
            """,
            new[]
            {
                "src/Some.Project/SomeProject.csproj",
                "src/Some.Project.Test/Some.Project.Test.csproj",
            },
        };
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