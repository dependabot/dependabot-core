using System.Text;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test;
using NuGetUpdater.Core.Test.Discover;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Cli.Test;

using TestFile = (string Path, string Content);

public partial class EntryPointTests
{
    public class Discover : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task PathWithSpaces()
        {
            await RunAsync(path =>
                [
                    "discover",
                    "--repo-root",
                    path,
                    "--workspace",
                    "path/to/some directory with spaces",
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                packages: [],
                initialFiles:
                [
                    ("path/to/some directory with spaces/project.csproj", """
                        <Project Sdk="Microsoft.NETSdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "path/to/some directory with spaces",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "path/to/some directory with spaces/project.csproj"),
                            ],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task WithSolution()
        {
            await RunAsync(path =>
                [
                    "discover",
                    "--repo-root",
                    path,
                    "--workspace",
                    "/",
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                ],
                initialFiles:
                new[]
                {
                    ("solution.sln", """
                        Microsoft Visual Studio Solution File, Format Version 12.00
                        # Visual Studio 14
                        VisualStudioVersion = 14.0.22705.0
                        MinimumVisualStudioVersion = 10.0.40219.1
                        Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "my", "path/to/my.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20C}"
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
                          EndGlobalSection
                          GlobalSection(SolutionProperties) = preSolution
                            HideSolutionNode = FALSE
                          EndGlobalSection
                        EndGlobal
                        """),
                    ("path/to/my.csproj", """
                        <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <ItemGroup>
                            <Reference Include="Some.Package">
                              <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <packages>
                          <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                        </packages>
                        """)
                },
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "path/to/my.csproj",
                            TargetFrameworks = ["net45"],
                            ReferencedProjectPaths = [],
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"]),
                            ],
                            Properties = [
                                new("TargetFrameworkVersion", "v4.5", "path/to/my.csproj"),
                            ],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task WithProject()
        {
            await RunAsync(path =>
                [
                    "discover",
                    "--repo-root",
                    path,
                    "--workspace",
                    "path/to",
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                ],
                initialFiles:
                new[]
                {
                    ("path/to/my.csproj", """
                        <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <ItemGroup>
                            <Reference Include="Some.Package">
                              <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <packages>
                          <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                        </packages>
                        """)
                },
                expectedResult: new()
                {
                    Path = "path/to",
                    Projects = [
                        new()
                        {
                            FilePath = "my.csproj",
                            TargetFrameworks = ["net45"],
                            ReferencedProjectPaths = [],
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"])
                            ],
                            Properties = [
                                new("TargetFrameworkVersion", "v4.5", "path/to/my.csproj"),
                            ],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task WithDirectory()
        {
            var workspacePath = "path/to/";
            await RunAsync(path =>
                [
                    "discover",
                    "--repo-root",
                    path,
                    "--workspace",
                    workspacePath,
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                ],
                initialFiles:
                new[]
                {
                    ("path/to/my.csproj", """
                        <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <None Include="packages.config" />
                          </ItemGroup>
                          <ItemGroup>
                            <Reference Include="Some.Package">
                              <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                              <Private>True</Private>
                            </Reference>
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/to/packages.config", """
                        <packages>
                          <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                        </packages>
                        """)
                },
                expectedResult: new()
                {
                    Path = workspacePath,
                    Projects = [
                        new()
                        {
                            FilePath = "my.csproj",
                            TargetFrameworks = ["net45"],
                            ReferencedProjectPaths = [],
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"])
                            ],
                            Properties = [
                                new("TargetFrameworkVersion", "v4.5", "path/to/my.csproj"),
                            ],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task WithDuplicateDependenciesOfDifferentTypes()
        {
            await RunAsync(path =>
                [
                    "discover",
                    "--repo-root",
                    path,
                    "--workspace",
                    "path/to",
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName)
                ],
                new[]
                {
                    ("path/to/my.csproj", """
                        <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Newtonsoft.Json" Version="7.0.1" />
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                        </Project>
                        """),
                    ("path/Directory.Build.props", """
                        <Project>
                            <ItemGroup Condition="'$(ManagePackageVersionsCentrally)' == 'true'">
                              <GlobalPackageReference Include="System.Text.Json" Version="8.0.3" />
                            </ItemGroup>
                            <ItemGroup Condition="'$(ManagePackageVersionsCentrally)' != 'true'">
                              <PackageReference Include="System.Text.Json" Version="8.0.3" />
                            </ItemGroup>
                        </Project>
                        """)
                },
                expectedResult: new()
                {
                    Path = "path/to",
                    Projects = [
                        new()
                        {
                            FilePath = "my.csproj",
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("Newtonsoft.Json", "7.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                                // $(ManagePackageVersionsCentrally) evaluates false by default, we only get a PackageReference
                                new("System.Text.Json", "8.0.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"])
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "path/to/my.csproj"),
                            ],
                        },
                        new()
                        {
                            FilePath = "../Directory.Build.props",
                            ReferencedProjectPaths = [],
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("System.Text.Json", "8.0.3", DependencyType.PackageReference, IsDirect: true),
                                new("System.Text.Json", "8.0.3", DependencyType.GlobalPackageReference, IsDirect: true)
                            ],
                            Properties = [],
                        }
                    ]
                }
            );
        }

        private static async Task RunAsync(
            Func<string, string[]> getArgs,
            TestFile[] initialFiles,
            ExpectedWorkspaceDiscoveryResult expectedResult,
            MockNuGetPackage[]? packages = null)
        {
            var actualResult = await RunDiscoveryAsync(initialFiles, async path =>
            {
                expectedResult = expectedResult with { Path = Path.Combine(path, expectedResult.Path) };

                var sb = new StringBuilder();
                var writer = new StringWriter(sb);

                var originalOut = Console.Out;
                var originalErr = Console.Error;
                Console.SetOut(writer);
                Console.SetError(writer);

                try
                {
                    await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, path);
                    var args = getArgs(path);
                    var result = await Program.Main(args);
                    if (result != 0)
                    {
                        throw new Exception($"Program exited with code {result}.\nOutput:\n\n{sb}");
                    }
                }
                finally
                {
                    Console.SetOut(originalOut);
                    Console.SetError(originalErr);
                }
            });

            ValidateWorkspaceResult(expectedResult, actualResult);
        }
    }
}
