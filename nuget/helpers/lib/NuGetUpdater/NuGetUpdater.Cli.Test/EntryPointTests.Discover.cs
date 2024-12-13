using System.Text;
using System.Text.Json;

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
        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task PathWithSpaces(bool useDirectDiscovery)
        {
            await RunAsync(path =>
                [
                    "discover",
                    "--job-path",
                    Path.Combine(path, "job.json"),
                    "--repo-root",
                    path,
                    "--workspace",
                    "path/to/some directory with spaces",
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
                ],
                initialFiles:
                [
                    ("path/to/some directory with spaces/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
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
                            Dependencies = [
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "path/to/some directory with spaces/project.csproj"),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task WithSolution(bool useDirectDiscovery)
        {
            await RunAsync(path =>
                [
                    "discover",
                    "--job-path",
                    Path.Combine(path, "job.json"),
                    "--repo-root",
                    path,
                    "--workspace",
                    "/",
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
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
                            Dependencies = [
                                new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"]),
                            ],
                            Properties = [],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "packages.config"
                            ],
                        }
                    ]
                }
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task WithProject(bool useDirectDiscovery)
        {
            await RunAsync(path =>
                [
                    "discover",
                    "--job-path",
                    Path.Combine(path, "job.json"),
                    "--repo-root",
                    path,
                    "--workspace",
                    "path/to",
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
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
                            Dependencies = [
                                new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"])
                            ],
                            Properties = [],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "packages.config"
                            ],
                        }
                    ]
                }
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task WithDirectory(bool useDirectDiscovery)
        {
            var workspacePath = "path/to/";
            await RunAsync(path =>
                [
                    "discover",
                    "--job-path",
                    Path.Combine(path, "job.json"),
                    "--repo-root",
                    path,
                    "--workspace",
                    workspacePath,
                    "--output",
                    Path.Combine(path, DiscoveryWorker.DiscoveryResultFileName),
                ],
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
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
                            Dependencies = [
                                new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"])
                            ],
                            Properties = [],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "packages.config"
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
                    "--job-path",
                    Path.Combine(path, "job.json"),
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
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                            <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("path/Directory.Build.props", """
                        <Project>
                            <ItemGroup Condition="'$(ManagePackageVersionsCentrally)' != 'true'">
                              <PackageReference Include="Package.B" Version="4.5.6" />
                            </ItemGroup>
                            <ItemGroup Condition="'$(ManagePackageVersionsCentrally)' == 'true'">
                              <GlobalPackageReference Include="Package.B" Version="7.8.9" />
                            </ItemGroup>
                        </Project>
                        """)
                },
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net8.0"),
                ],
                expectedResult: new()
                {
                    Path = "path/to",
                    Projects = [
                        new()
                        {
                            FilePath = "my.csproj",
                            TargetFrameworks = ["net8.0"],
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("ManagePackageVersionsCentrally", "false", "path/to/my.csproj"),
                                new("TargetFramework", "net8.0", "path/to/my.csproj"),
                            ],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "../Directory.Build.props"
                            ],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        private static async Task RunAsync(
            Func<string, string[]> getArgs,
            TestFile[] initialFiles,
            ExpectedWorkspaceDiscoveryResult expectedResult,
            MockNuGetPackage[]? packages = null,
            ExperimentsManager? experimentsManager = null
        )
        {
            experimentsManager ??= new ExperimentsManager();
            var actualResult = await RunDiscoveryAsync(initialFiles, async path =>
            {
                var sb = new StringBuilder();
                var writer = new StringWriter(sb);

                var originalOut = Console.Out;
                var originalErr = Console.Error;
                Console.SetOut(writer);
                Console.SetError(writer);

                try
                {
                    await UpdateWorkerTestBase.MockJobFileInDirectory(path, experimentsManager);
                    await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, path);
                    var args = getArgs(path);

                    // manually pull out the experiments manager for the validate step below
                    for (int i = 0; i < args.Length - 1; i++)
                    {
                        if (args[i] == "--job-path")
                        {
                            experimentsManager = await ExperimentsManager.FromJobFileAsync(args[i + 1], new TestLogger());
                        }
                    }

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

                var resultPath = Path.Join(path, DiscoveryWorker.DiscoveryResultFileName);
                var resultJson = await File.ReadAllTextAsync(resultPath);
                var resultObject = JsonSerializer.Deserialize<WorkspaceDiscoveryResult>(resultJson, DiscoveryWorker.SerializerOptions);
                return resultObject!;
            });

            ValidateWorkspaceResult(expectedResult, actualResult, experimentsManager);
        }
    }
}
