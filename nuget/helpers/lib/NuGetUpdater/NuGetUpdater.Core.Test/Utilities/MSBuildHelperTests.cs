using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

using Microsoft.Language.Xml;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class MSBuildHelperTests
{
    public MSBuildHelperTests()
    {
        MSBuildHelper.RegisterMSBuild();
    }

    [Theory]
    [MemberData(nameof(SolutionProjectPathTestData))]
    public void ProjectPathsCanBeParsedFromSolutionFiles(string solutionContent, string[] expectedProjectSubPaths)
    {
        var solutionPath = Path.GetTempFileName();
        var solutionDirectory = Path.GetDirectoryName(solutionPath)!;
        try
        {
            File.WriteAllText(solutionPath, solutionContent);
            var actualProjectSubPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath).ToArray();
            var expectedPaths = expectedProjectSubPaths.Select(path => Path.Combine(solutionDirectory, path)).ToArray();
            if (Environment.OSVersion.Platform == PlatformID.Win32NT)
            {
                // make the test happy when running on Windows
                expectedPaths = expectedPaths.Select(p => p.Replace("/", "\\")).ToArray();
            }

            Assert.Equal(expectedPaths, actualProjectSubPaths);
        }
        finally
        {
            File.Delete(solutionPath);
        }
    }

    [Theory]
    [InlineData("<Project><PropertyGroup><TargetFramework>netstandard2.0</TargetFramework></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>netstandard2.0</TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>  ; netstandard2.0 ; </TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>netstandard2.0 ; netstandard2.1 ; </TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", "netstandard2.1")]
    [InlineData("<Project><SomeTopLevelProperty>42</SomeTopLevelProperty><PropertyGroup><TargetFramework>netstandard2.0</TargetFramework></PropertyGroup></Project>", "netstandard2.0", null)]
    public void TfmsCanBeDeterminedFromProjectContents(string projectContents, string? expectedTfm1, string? expectedTfm2)
    {
        var projectPath = Path.GetTempFileName();
        try
        {
            File.WriteAllText(projectPath, projectContents);
            var expectedTfms = new[] { expectedTfm1, expectedTfm2 }.Where(tfm => tfm is not null).ToArray();
            var buildFile = new BuildFile(Path.GetDirectoryName(projectPath)!, projectPath, Parser.ParseText(projectContents));
            var actualTfms = MSBuildHelper.GetTargetFrameworkMonikers(ImmutableArray.Create(buildFile));
            Assert.Equal(expectedTfms, actualTfms);
        }
        finally
        {
            File.Delete(projectPath);
        }
    }

    [Theory]
    [MemberData(nameof(GetTopLevelPackageDependenyInfosTestData))]
    public async Task TopLevelPackageDependenciesCanBeDetermined((string Path, string Content)[] buildFileContents, (string PackageName, string Version)[] expectedTopLevelDependencies)
    {
        using var testDirectory = new TemporaryDirectory();
        var buildFiles = new List<BuildFile>();
        foreach (var (path, content) in buildFileContents)
        {
            var fullPath = Path.Combine(testDirectory.DirectoryPath, path);
            await File.WriteAllTextAsync(fullPath, content);
            buildFiles.Add(new BuildFile(testDirectory.DirectoryPath, fullPath, Parser.ParseText(content)));
        }

        var actualTopLevelDependencies = MSBuildHelper.GetTopLevelPackageDependenyInfos(buildFiles.ToImmutableArray());
        Assert.Equal(expectedTopLevelDependencies, actualTopLevelDependencies);
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
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(temp.DirectoryPath, "netstandard2.0", new[] { (PackageName: "Microsoft.Extensions.Http", VersionString: "7.0.0") });
        Assert.Equal(expectedDependencies, actualDependencies);
    }

    [Fact]
    public async Task AllPackageDependenciesCanBeFoundWithNuGetConfig()
    {
        // It is important to clear all NuGet caches for this test.
        await ProcessEx.RunAsync("dotnet", $"nuget locals -c all");

        using var temp = new TemporaryDirectory();

        // First validate that we are unable to find dependencies for the package version without a NuGet.config.
        var dependenciesNoNuGetConfig = await MSBuildHelper.GetAllPackageDependenciesAsync(temp.DirectoryPath, "netstandard2.0", new[] { (PackageName: "Microsoft.CodeAnalysis.Common", VersionString: "4.8.0-3.23457.5") });
        Assert.Equal(Array.Empty<(string PackageName, string Version)>(), dependenciesNoNuGetConfig);

        // Write the NuGet.config and try again.
        await File.WriteAllTextAsync(Path.Combine(temp.DirectoryPath, "NuGet.Config"), """
            <?xml version="1.0" encoding="utf-8"?>
            <configuration>
              <packageSources>
                <clear />
                <add key="dotnet-tools" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-tools/nuget/v3/index.json" />
                <add key="dotnet-public" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-public/nuget/v3/index.json" />
              </packageSources>
            </configuration>
            """);

        var expectedDependencies = new[]
        {
            ("Microsoft.CodeAnalysis.Common", "4.8.0-3.23457.5"),
            ("System.Buffers", "4.5.1"),
            ("System.Collections.Immutable", "7.0.0"),
            ("System.Memory", "4.5.5"),
            ("System.Numerics.Vectors", "4.4.0"),
            ("System.Reflection.Metadata", "7.0.0"),
            ("System.Runtime.CompilerServices.Unsafe", "6.0.0"),
            ("System.Text.Encoding.CodePages", "7.0.0"),
            ("System.Threading.Tasks.Extensions", "4.5.4"),
            ("Microsoft.CodeAnalysis.Analyzers", "3.3.4"),
        };
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(temp.DirectoryPath, "netstandard2.0", new[] { (PackageName: "Microsoft.CodeAnalysis.Common", VersionString: "4.8.0-3.23457.5") });
        Assert.Equal(expectedDependencies, actualDependencies);
    }

    public static IEnumerable<object[]> GetTopLevelPackageDependenyInfosTestData()
    {
        // simple case
        yield return new object[]
        {
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new[]
            {
                ("Newtonsoft.Json", "12.0.1")
            }
        };

        // version is in property in same file
        yield return new object[]
        {
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <NewtonsoftJsonVersion>12.0.1</NewtonsoftJsonVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new[]
            {
                ("Newtonsoft.Json", "12.0.1")
            }
        };

        // project file has invalid top level property
        yield return new object[]
        {
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <SomeInvalidProperty>42</SomeInvalidProperty>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new[]
            {
                ("Newtonsoft.Json", "12.0.1")
            }
        };
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
}