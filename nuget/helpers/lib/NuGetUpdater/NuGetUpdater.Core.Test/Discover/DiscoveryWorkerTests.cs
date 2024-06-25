using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests : DiscoveryWorkerTestBase
{
    [Theory]
    [InlineData("src/project.csproj")]
    [InlineData("src/project.vbproj")]
    [InlineData("src/project.fsproj")]
    public async Task TestProjectFiles(string projectPath)
    {
        await TestDiscoveryAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
            ],
            workspacePath: "src",
            files: new[]
            {
                (projectPath, """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion>9.0.1</SomePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            expectedResult: new()
            {
                FilePath = "src",
                Projects = [
                    new()
                    {
                        FilePath = Path.GetFileName(projectPath),
                        TargetFrameworks = ["net8.0"],
                        ReferencedProjectPaths = [],
                        ExpectedDependencyCount = 2,
                        Dependencies = [
                            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("SomePackageVersion", "9.0.1", projectPath),
                            new("TargetFramework", "net8.0", projectPath),
                        ]
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task TestPackageConfig()
    {
        await TestDiscoveryAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
            ],
            workspacePath: "src",
            files: new[]
            {
                ("src/project.csproj", """
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
                ("src/packages.config", """
                    <packages>
                      <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                    </packages>
                    """),
            },
            expectedResult: new()
            {
                FilePath = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net45"],
                        ReferencedProjectPaths = [],
                        ExpectedDependencyCount = 2,
                        Dependencies = [
                            new("Microsoft.NETFramework.ReferenceAssemblies", "1.0.3", DependencyType.Unknown, TargetFrameworks: ["net45"], IsTransitive: true),
                            new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"]),
                        ],
                        Properties = [
                            new("TargetFrameworkVersion", "v4.5", "src/project.csproj"),
                        ]
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task TestProps()
    {
        await TestDiscoveryAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
            ],
            workspacePath: "src",
            files: new[]
            {
                ("src/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Build.props", "<Project />"),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <SomePackageVersion>9.0.1</SomePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            expectedResult: new()
            {
                FilePath = "src",
                ExpectedProjectCount = 2,
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        ReferencedProjectPaths = [],
                        ExpectedDependencyCount = 2,
                        Dependencies = [
                            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("SomePackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFramework", "net8.0", "src/project.csproj"),
                        ]
                    }
                ],
                DirectoryPackagesProps = new()
                {
                    FilePath = "../Directory.Packages.props",
                    Dependencies = [
                        new("Some.Package", "9.0.1", DependencyType.PackageVersion, IsDirect: true)
                    ],
                }
            }
        );
    }

    [Fact]
    public async Task TestRepo()
    {
        var solutionPath = "solution.sln";
        await TestDiscoveryAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
            ],
            workspacePath: "",
            files: new[]
            {
                ("src/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Build.props", "<Project />"),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <SomePackageVersion>9.0.1</SomePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """),
                (solutionPath, """
                    Microsoft Visual Studio Solution File, Format Version 12.00
                    # Visual Studio 14
                    VisualStudioVersion = 14.0.22705.0
                    MinimumVisualStudioVersion = 10.0.40219.1
                    Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "project", ".\src\project.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20C}"
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
                ("global.json", """
                    {
                      "sdk": {
                        "version": "6.0.405",
                        "rollForward": "latestPatch"
                      },
                      "msbuild-sdks": {
                        "My.Custom.Sdk": "5.0.0",
                        "My.Other.Sdk": "1.0.0-beta"
                      }
                    }
                    """),
                (".config/dotnet-tools.json", """
                    {
                      "version": 1,
                      "isRoot": true,
                      "tools": {
                        "microsoft.botsay": {
                          "version": "1.0.0",
                          "commands": [
                            "botsay"
                          ]
                        },
                        "dotnetsay": {
                          "version": "2.1.3",
                          "commands": [
                            "dotnetsay"
                          ]
                        }
                      }
                    }
                    """),
            },
            expectedResult: new()
            {
                FilePath = "",
                ExpectedProjectCount = 2,
                Projects = [
                    new()
                    {
                        FilePath = "src/project.csproj",
                        TargetFrameworks = ["net7.0", "net8.0"],
                        ExpectedDependencyCount = 2,
                        Dependencies = [
                            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net7.0", "net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("SomePackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFrameworks", "net7.0;net8.0", "src/project.csproj"),
                        ]
                    }
                ],
                DirectoryPackagesProps = new()
                {
                    FilePath = "Directory.Packages.props",
                    Dependencies = [
                        new("Some.Package", "9.0.1", DependencyType.PackageVersion, IsDirect: true)
                    ],
                },
                GlobalJson = new()
                {
                    FilePath = "global.json",
                    Dependencies = [
                        new("Microsoft.NET.Sdk", "6.0.405", DependencyType.MSBuildSdk),
                        new("My.Custom.Sdk", "5.0.0", DependencyType.MSBuildSdk),
                        new("My.Other.Sdk", "1.0.0-beta", DependencyType.MSBuildSdk),
                    ]
                },
                DotNetToolsJson = new()
                {
                    FilePath = ".config/dotnet-tools.json",
                    Dependencies = [
                        new("microsoft.botsay", "1.0.0", DependencyType.DotNetTool),
                        new("dotnetsay", "2.1.3", DependencyType.DotNetTool),
                    ]
                }
            }
        );
    }
}
