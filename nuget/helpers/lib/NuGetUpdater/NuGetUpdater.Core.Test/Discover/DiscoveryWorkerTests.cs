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
            workspacePath: "src",
            files: new[]
            {
                (projectPath, """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
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
                        TargetFrameworks = ["netstandard2.0"],
                        ReferencedProjectPaths = [],
                        ExpectedDependencyCount = 19,
                        Dependencies = [
                            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                            new("Newtonsoft.Json", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["netstandard2.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("NewtonsoftJsonPackageVersion", "9.0.1", projectPath),
                            new("TargetFramework", "netstandard2.0", projectPath),
                        ]
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task TestPackageConfig()
    {
        var projectPath = "src/project.csproj";
        await TestDiscoveryAsync(
            workspacePath: "",
            files: new[]
            {
                (projectPath, """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """),
                ("src/packages.config", """
                    <packages>
                      <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
                    </packages>
                    """),
            },
            expectedResult: new()
            {
                FilePath = "",
                Projects = [
                    new()
                    {
                        FilePath = projectPath,
                        TargetFrameworks = ["net45"],
                        ReferencedProjectPaths = [],
                        ExpectedDependencyCount = 2, // Should we ignore Microsoft.NET.ReferenceAssemblies?
                        Dependencies = [
                            new("Newtonsoft.Json", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"])
                        ],
                        Properties = [
                            new("TargetFrameworkVersion", "v4.5", projectPath),
                        ]
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task TestProps()
    {
        var projectPath = "src/project.csproj";
        await TestDiscoveryAsync(
            workspacePath: "",
            files: new[]
            {
                (projectPath, """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            expectedResult: new()
            {
                FilePath = "",
                Projects = [
                    new()
                    {
                        FilePath = projectPath,
                        TargetFrameworks = ["netstandard2.0"],
                        ReferencedProjectPaths = [],
                        ExpectedDependencyCount = 19,
                        Dependencies = [
                            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                            new("Newtonsoft.Json", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["netstandard2.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("NewtonsoftJsonPackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFramework", "netstandard2.0", projectPath),
                        ]
                    }
                ],
                DirectoryPackagesProps = new()
                {
                    FilePath = "Directory.Packages.props",
                    Dependencies = [
                        new("Newtonsoft.Json", "9.0.1", DependencyType.PackageVersion, IsDirect: true)
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
            workspacePath: "",
            files: new[]
            {
                ("src/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>netstandard2.0;net6.0</TargetFrameworks>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
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
                Projects = [
                    new()
                    {
                        FilePath = "src/project.csproj",
                        TargetFrameworks = ["net6.0", "netstandard2.0"],
                        ExpectedDependencyCount = 19,
                        Dependencies = [
                            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
                            new("Newtonsoft.Json", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net6.0", "netstandard2.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("NewtonsoftJsonPackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFrameworks", "netstandard2.0;net6.0", "src/project.csproj"),
                        ]
                    }
                ],
                DirectoryPackagesProps = new()
                {
                    FilePath = "Directory.Packages.props",
                    Dependencies = [
                        new("Newtonsoft.Json", "9.0.1", DependencyType.PackageVersion, IsDirect: true)
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
