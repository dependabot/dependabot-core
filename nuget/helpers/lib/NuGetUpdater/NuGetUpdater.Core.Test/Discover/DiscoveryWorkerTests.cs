using System.Collections.Immutable;
using System.Text.Json;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests : DiscoveryWorkerTestBase
{
    [Theory]
    [InlineData("src/project.csproj", true)]
    [InlineData("src/project.csproj", false)]
    [InlineData("src/project.vbproj", true)]
    [InlineData("src/project.vbproj", false)]
    [InlineData("src/project.fsproj", true)]
    [InlineData("src/project.fsproj", false)]
    public async Task TestProjectFiles(string projectPath, bool useDirectDiscovery)
    {
        var expectedDependencies = new List<Dependency>()
        {
            new Dependency("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
        };
        if (useDirectDiscovery && Path.GetExtension(projectPath)! == ".fsproj")
        {
            // this package ships with the SDK and is automatically added for F# projects but should be manually added here to make the test consistent
            // only direct package discovery finds this, though
            expectedDependencies.Add(new Dependency("FSharp.Core", "9.0.100", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true));
        }

        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
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
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = Path.GetFileName(projectPath),
                        TargetFrameworks = ["net8.0"],
                        Dependencies = expectedDependencies.ToImmutableArray(),
                        Properties = [
                            new("SomePackageVersion", "9.0.1", projectPath),
                            new("TargetFramework", "net8.0", projectPath),
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
    public async Task FindDependenciesFromSDKProjectsWithDesktopTFM(bool useDirectDiscovery)
    {
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net472"),
            ],
            workspacePath: "src",
            files:
            [
                ("src/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net472</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedResult: new()
            {
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net472"],
                        Dependencies = [
                            new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net472"], IsDirect: true)
                        ],
                        Properties = [
                            new("TargetFramework", "net472", "src/project.csproj"),
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
    public async Task TestDependencyWithTrailingSpacesInAttribute(bool useDirectDiscovery)
    {
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
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
                        <SomePackageVersion>9.0.1</SomePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include=" Some.Package    " Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            expectedResult: new()
            {
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("SomePackageVersion", "9.0.1", "src/project.csproj"),
                            new("TargetFramework", "net8.0", "src/project.csproj"),
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task TestDependenciesSeparatedBySemicolon()
    {
        await TestDiscoveryAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "9.0.1", "net8.0"),
            ],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            workspacePath: "src",
            files: new[]
            {
                ("src/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion>9.0.1</SomePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package;Some.Package2" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            expectedResult: new()
            {
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        ReferencedProjectPaths = [],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            new("Some.Package2", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        ],
                        Properties = [
                            new("SomePackageVersion", "9.0.1", "src/project.csproj"),
                            new("TargetFramework", "net8.0", "src/project.csproj"),
                        ],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    }
                ]
            }
        );
    }

    [LinuxOnlyFact]
    public async Task TestDependenciesCaseSensitiveProjectPaths()
    {
        await TestDiscoveryAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
            ],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            workspacePath: "src",
            files: new[]
            {
                ("src/test/project1/project1.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """),
                ("src/TEST/project2/project2.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """),
                // Add solution files
                ("src/solution.sln", """
                    Microsoft Visual Studio Solution File, Format Version 12.00
                    # Visual Studio 14
                    VisualStudioVersion = 14.0.22705.0
                    MinimumVisualStudioVersion = 10.0.40219.1
                    Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "project1", "test\project1\project1.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20C}"
                    EndProject
                    Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "project2", "test\project2\project2.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20D}"
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
                        {782E0C0A-10D3-444D-9640-263D03D2B20D}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
                        {782E0C0A-10D3-444D-9640-263D03D2B20D}.Debug|Any CPU.Build.0 = Debug|Any CPU
                        {782E0C0A-10D3-444D-9640-263D03D2B20D}.Release|Any CPU.ActiveCfg = Release|Any CPU
                        {782E0C0A-10D3-444D-9640-263D03D2B20D}.Release|Any CPU.Build.0 = Release|Any CPU
                      EndGlobalSection
                      GlobalSection(SolutionProperties) = preSolution
                        HideSolutionNode = FALSE
                      EndGlobalSection
                    EndGlobal
                    """)

            },
            expectedResult: new()
            {
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "test/project1/project1.csproj",
                        TargetFrameworks = ["net8.0"],
                        ReferencedProjectPaths = [],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        ],
                        Properties = [
                            new("TargetFramework", "net8.0", "src/test/project1/project1.csproj"),
                        ],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    },
                    new()
                    {
                        FilePath = "TEST/project2/project2.csproj",
                        TargetFrameworks = ["net8.0"],
                        ReferencedProjectPaths = [],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        ],
                        Properties = [
                            new("TargetFramework", "net8.0", "src/TEST/project2/project2.csproj"),
                        ],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task TestDependenciesSeparatedBySemicolonWithWhitespace()
    {
        await TestDiscoveryAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Package2", "9.0.1", "net8.0"),
            ],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            workspacePath: "src",
            files: new[]
            {
                ("src/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion>9.0.1</SomePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include=" Some.Package ; Some.Package2 " Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            expectedResult: new()
            {
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        ReferencedProjectPaths = [],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            new("Some.Package2", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        ],
                        Properties = [
                            new("SomePackageVersion", "9.0.1", "src/project.csproj"),
                            new("TargetFramework", "net8.0", "src/project.csproj"),
                        ],
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
    public async Task TestPackageConfig(bool useDirectDiscovery)
    {
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
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
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net45"],
                        Dependencies = [
                            new("Some.Package", "7.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net45"]),
                        ],
                        Properties = [],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [],
                        AdditionalFiles = [
                            "packages.config",
                        ],
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task TestProps_DirectDiscovery()
    {
        await TestDiscoveryAsync(
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
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
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("TargetFramework", "net8.0", "src/project.csproj")
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [
                            "../Directory.Build.props",
                            "../Directory.Packages.props",
                        ],
                        AdditionalFiles = [],
                    }
                ],
            }
        );
    }

    [Fact]
    public async Task TestProps_NoDirectDiscovery()
    {
        await TestDiscoveryAsync(
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
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
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("SomePackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFramework", "net8.0", "src/project.csproj")
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [
                            "../Directory.Build.props",
                            "../Directory.Packages.props",
                        ],
                        AdditionalFiles = [],
                    }
                ],
            }
        );
    }

    [Fact]
    public async Task TestRepo_DirectDiscovery()
    {
        var solutionPath = "solution.sln";
        await TestDiscoveryAsync(
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net7.0"),
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
                Path = "",
                Projects = [
                    new()
                    {
                        FilePath = "src/project.csproj",
                        TargetFrameworks = ["net7.0", "net8.0"],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        ],
                        Properties = [
                            new("TargetFrameworks", "net7.0;net8.0", "src/project.csproj")
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [
                            "../Directory.Build.props",
                            "../Directory.Packages.props",
                        ],
                        AdditionalFiles = [],
                    }
                ],
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

    [Fact]
    public async Task TestRepo_SolutionFileCasingMismatchIsResolved()
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
                    Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "ProJect", ".\src\ProJect.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20C}"
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
            },
            expectedResult: new()
            {
                Path = "",
                Projects = [
                    new()
                    {
                        FilePath = "src/project.csproj",
                        TargetFrameworks = ["net7.0", "net8.0"],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net7.0", "net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("SomePackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFrameworks", "net7.0;net8.0", "src/project.csproj"),
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [
                            "../Directory.Build.props",
                            "../Directory.Packages.props",
                        ],
                        AdditionalFiles = [],
                    }
                ],
            }
        );
    }

    [Fact]
    public async Task TestDirsProj_CasingMismatchIsResolved()
    {
        var dirsProjPath = "dirs.proj";
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
            // Introduce a casing difference in the project reference
            (dirsProjPath, """
                <Project>
                  <ItemGroup>
                    <ProjectReference Include="SRC/PROJECT.CSPROJ" />
                  </ItemGroup>
                </Project>
                """)
            },
            expectedResult: new()
            {
                Path = "",
                Projects = [
                    new()
                    {
                        FilePath = "src/project.csproj",
                        TargetFrameworks = ["net7.0", "net8.0"],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net7.0", "net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("SomePackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFrameworks", "net7.0;net8.0", "src/project.csproj"),
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [
                            "../Directory.Build.props",
                            "../Directory.Packages.props",
                        ],
                        AdditionalFiles = [],
                    }
                ],
            }
        );
    }

    [Fact]
    public async Task TestRepo_NoDirectDiscovery()
    {
        var solutionPath = "solution.sln";
        await TestDiscoveryAsync(
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net7.0"),
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
                Path = "",
                Projects = [
                    new()
                    {
                        FilePath = "src/project.csproj",
                        TargetFrameworks = ["net7.0", "net8.0"],
                        Dependencies = [
                            new("Some.Package", "9.0.1", DependencyType.PackageReference, TargetFrameworks: ["net7.0", "net8.0"], IsDirect: true),
                        ],
                        Properties = [
                            new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                            new("SomePackageVersion", "9.0.1", "Directory.Packages.props"),
                            new("TargetFrameworks", "net7.0;net8.0", "src/project.csproj")
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [
                            "../Directory.Build.props",
                            "../Directory.Packages.props",
                        ],
                        AdditionalFiles = [],
                    }
                ],
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

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task NonSupportedProjectExtensionsAreSkipped(bool useDirectDiscovery)
    {
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
            ],
            workspacePath: "/",
            files: new[]
            {
                ("solution.sln", """
                    Microsoft Visual Studio Solution File, Format Version 12.00
                    # Visual Studio Version 17
                    VisualStudioVersion = 17.10.35027.167
                    MinimumVisualStudioVersion = 10.0.40219.1
                    Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "supported", "src\supported.csproj", "{4A3B8D8A-A585-4593-8AF3-DED05AE3C40F}"
                    EndProject
                    Project("{54435603-DBB4-11D2-8724-00A0C9A8B90C}") = "unsupported", "src\unsupported.vdproj", "{271E533C-8A44-4572-8C18-CD65A79F8658}"
                    EndProject
                    Global
                    	GlobalSection(SolutionConfigurationPlatforms) = preSolution
                    		Debug|Any CPU = Debug|Any CPU
                    		Release|Any CPU = Release|Any CPU
                    	EndGlobalSection
                    	GlobalSection(ProjectConfigurationPlatforms) = postSolution
                    		{4A3B8D8A-A585-4593-8AF3-DED05AE3C40F}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
                    		{4A3B8D8A-A585-4593-8AF3-DED05AE3C40F}.Debug|Any CPU.Build.0 = Debug|Any CPU
                    		{4A3B8D8A-A585-4593-8AF3-DED05AE3C40F}.Release|Any CPU.ActiveCfg = Release|Any CPU
                    		{4A3B8D8A-A585-4593-8AF3-DED05AE3C40F}.Release|Any CPU.Build.0 = Release|Any CPU
                    		{271E533C-8A44-4572-8C18-CD65A79F8658}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
                    		{271E533C-8A44-4572-8C18-CD65A79F8658}.Debug|Any CPU.Build.0 = Debug|Any CPU
                    		{271E533C-8A44-4572-8C18-CD65A79F8658}.Release|Any CPU.ActiveCfg = Release|Any CPU
                    		{271E533C-8A44-4572-8C18-CD65A79F8658}.Release|Any CPU.Build.0 = Release|Any CPU
                    	EndGlobalSection
                    	GlobalSection(SolutionProperties) = preSolution
                    		HideSolutionNode = FALSE
                    	EndGlobalSection
                    	GlobalSection(ExtensibilityGlobals) = postSolution
                    		SolutionGuid = {EE5BDEF7-1D4D-4773-9659-FC4A3846CD6D}
                    	EndGlobalSection
                    EndGlobal
                    """),
                ("src/supported.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("src/unsupported.vdproj", """
                    "DeployProject"
                    {
                    "SomeKey" = "SomeValue"
                    }
                    """),
            },
            expectedResult: new()
            {
                Path = "",
                Projects = [
                    new()
                    {
                        FilePath = "src/supported.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("TargetFramework", "net8.0", @"src/supported.csproj"),
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
    public async Task DiscoveryReportsDependencyFileNotParseable(bool useDirectDiscovery)
    {
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
            workspacePath: "",
            files:
            [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
                  ("project2.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference: Include="Some.Package2" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            expectedResult: new()
            {
                Path = "",
                Projects = [],
                Error = new DependencyFileNotParseable("project2.csproj"),
            });
    }

    [Fact]
    public async Task ResultFileHasCorrectShapeForAuthenticationFailure()
    {
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync([]);
        var discoveryResultPath = Path.Combine(temporaryDirectory.DirectoryPath, DiscoveryWorker.DiscoveryResultFileName);
        await DiscoveryWorker.WriteResultsAsync(temporaryDirectory.DirectoryPath, discoveryResultPath, new()
        {
            Error = new PrivateSourceAuthenticationFailure(["<some package feed>"]),
            Path = "/",
            Projects = [],
        });
        var discoveryContents = await File.ReadAllTextAsync(discoveryResultPath);

        // raw result file should look like this:
        // {
        //   ...
        //   "Error": {
        //     "error-type": "private_source_authentication_failure",
        //     "error-detail": {
        //       "source": "(<some package feed>)"
        //     }
        //   }
        //   ...
        // }
        var jsonDocument = JsonDocument.Parse(discoveryContents);
        var error = jsonDocument.RootElement.GetProperty("Error");
        var errorType = error.GetProperty("error-type");
        var errorDetail = error.GetProperty("error-details");
        var errorSource = errorDetail.GetProperty("source");

        Assert.Equal("private_source_authentication_failure", errorType.GetString());
        Assert.Equal("(<some package feed>)", errorSource.GetString());
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task ReportsPrivateSourceAuthenticationFailure(bool useDirectDiscovery)
    {
        static (int, string) TestHttpHandler(string uriString)
        {
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                // initial request is good
                "/index.json" => (200, $$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/download",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/query",
                                "@type": "SearchQueryService"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl"
                            }
                        ]
                    }
                    """),
                // all other requests are unauthorized
                _ => (401, "{}"),
            };
        }
        // override various nuget locations
        using var tempDir = new TemporaryDirectory();
        using var _ = new TemporaryEnvironment(
        [
            ("NUGET_PACKAGES", Path.Combine(tempDir.DirectoryPath, "NUGET_PACKAGES")),
            ("NUGET_HTTP_CACHE_PATH", Path.Combine(tempDir.DirectoryPath, "NUGET_HTTP_CACHE_PATH")),
            ("NUGET_SCRATCH", Path.Combine(tempDir.DirectoryPath, "NUGET_SCRATCH")),
            ("NUGET_PLUGINS_CACHE_PATH", Path.Combine(tempDir.DirectoryPath, "NUGET_PLUGINS_CACHE_PATH")),
        ]);
        using var http = TestHttpServer.CreateTestStringServer(TestHttpHandler);
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
            workspacePath: "",
            files:
            [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="{http.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """),
            ],
            expectedResult: new()
            {
                Error = new PrivateSourceAuthenticationFailure([$"{http.BaseUrl.TrimEnd('/')}/index.json"]),
                Path = "",
                Projects = [],
            }
        );
    }

    [Fact]
    public async Task ReportsPrivateSourceBadResponseFailure()
    {
        static (int, string) TestHttpHandler(string uriString)
        {
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                // initial request is good
                "/index.json" => (200, $$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/download",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/query",
                                "@type": "SearchQueryService"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl"
                            }
                        ]
                    }
                    """),
                // all other requests are unauthorized
                _ => (429, "{}"),
            };
        }
        // override various nuget locations
        using var tempDir = new TemporaryDirectory();
        using var _ = new TemporaryEnvironment(
        [
            ("NUGET_PACKAGES", Path.Combine(tempDir.DirectoryPath, "NUGET_PACKAGES")),
            ("NUGET_HTTP_CACHE_PATH", Path.Combine(tempDir.DirectoryPath, "NUGET_HTTP_CACHE_PATH")),
            ("NUGET_SCRATCH", Path.Combine(tempDir.DirectoryPath, "NUGET_SCRATCH")),
            ("NUGET_PLUGINS_CACHE_PATH", Path.Combine(tempDir.DirectoryPath, "NUGET_PLUGINS_CACHE_PATH")),
        ]);
        using var http = TestHttpServer.CreateTestStringServer(TestHttpHandler);
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = true };
        await TestDiscoveryAsync(
            experimentsManager: experimentsManager,
            workspacePath: "",
            files:
            [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="{http.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """),
            ],
            expectedResult: new()
            {
                Error = new PrivateSourceBadResponse([$"{http.BaseUrl.TrimEnd('/')}/index.json"]),
                Path = "",
                Projects = [],
            }
        );
    }

    [LinuxOnlyFact]
    public async Task DiscoverySucceedsWhenNoWindowsAppRefPackageCanBeFound()
    {
        // this test mimics a package feed that doesn't have the common Microsoft.Windows.App.Ref package; common in Azure DevOps
        // Windows machines always have the package, so this test only makes sense on Linux
        await TestDiscoveryAsync(
            experimentsManager: new ExperimentsManager() { InstallDotnetSdks = true, UseDirectDiscovery = true },
            includeCommonPackages: false,
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
            ],
            workspacePath: "",
            files: [
                ("project.csproj", """
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
                Path = "",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("TargetFramework", "net8.0", "project.csproj"),
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task MissingPackageIsCorrectlyReported_PackageNotFound()
    {
        await TestDiscoveryAsync(
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0", [(null, [("Transitive.Dependency.Does.Not.Exist", "4.5.6")])]),
            ],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            workspacePath: "",
            files: [
                ("project.csproj", """
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
                Path = "",
                Projects = [],
                Error = new DependencyNotFound("Transitive.Dependency.Does.Not.Exist"),
            }
        );
    }

    [Fact]
    public async Task MissingPackageIsCorrectlyReported_VersionNotFound()
    {
        await TestDiscoveryAsync(
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0", [(null, [("Transitive.Dependency", "4.5.6")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "0.1.2", "net8.0"),
            ],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            workspacePath: "",
            files: [
                ("project.csproj", """
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
                Path = "",
                Projects = [],
                Error = new DependencyNotFound("Transitive.Dependency"),
            }
        );
    }

    [Fact]
    public async Task MissingFileIsReported()
    {
        await TestDiscoveryAsync(
            packages: [],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true, InstallDotnetSdks = true },
            workspacePath: "",
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="file-that-does-not-exist.props" />
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """)
            ],
            expectedResult: new()
            {
                Path = "",
                Projects = [],
                ErrorRegex = @"file-that-does-not-exist\.props",
            }
        );
    }

    // If the "Restore" target is invoked and $(RestoreUseStaticGraphEvaluation) is set to true, NuGet can throw
    // a NullReferenceException.
    // https://github.com/NuGet/Home/issues/11761#issuecomment-1105218996
    [Fact]
    public async Task NullReferenceExceptionFromNuGetRestoreIsWorkedAround()
    {
        await TestDiscoveryAsync(
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
            ],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            workspacePath: "",
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <RestoreUseStaticGraphEvaluation>true</RestoreUseStaticGraphEvaluation>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
                // a pattern seen in the wild; always run restore
                ("Directory.Build.rsp", """
                    /Restore
                    """)
            ],
            expectedResult: new()
            {
                Path = "",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                        ],
                        Properties = [
                            new("RestoreUseStaticGraphEvaluation", "true", "project.csproj"),
                            new("TargetFramework", "net8.0", "project.csproj"),
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = [],
                        AdditionalFiles = [],
                    }
                ]
            }
        );
    }

    [Fact]
    public async Task CentralPackageManagementStillWorksWithMultipleFeedsListedInConfig()
    {
        // If a repo doesn't contain a `NuGet.Config` file and `dependabot.yml` specifies a package source, a user-
        // local `NuGet.Config` file is created before the updater is run that enumerates the specified feeds as well
        // as `api.nuget.org`.  If a given project is using Central Package Management a warning NU1507 will be
        // generated because of the multiple feeds listed.  If that project _also_ specifies $(TreatWarningsAsErrors)
        // as true, this will cause dependency discovery to "fail".  To simulate this, multiple remote NuGet sources
        // need to be listed in the `NuGet.Config` file in this test.
        using var http1 = TestHttpServer.CreateTestNuGetFeed(MockNuGetPackage.CreateSimplePackage("Package1", "1.0.0", "net9.0"));
        using var http2 = TestHttpServer.CreateTestNuGetFeed(MockNuGetPackage.CreateSimplePackage("Package2", "2.0.0", "net9.0"));
        await TestDiscoveryAsync(
            packages: [],
            experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
            workspacePath: "/src",
            files: [
                ("src/NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <!-- explicitly _not_ calling "clear" because we also want the upstream sources in addition to these two remote sources -->
                        <add key="source_1" value="{http1.GetPackageFeedIndex()}" allowInsecureConnections="true" />
                        <add key="source_2" value="{http2.GetPackageFeedIndex()}" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """),
                ("src/project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                        <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
                        <MSBuildTreatWarningsAsErrors>true</MSBuildTreatWarningsAsErrors>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package1" />
                        <PackageReference Include="Package2" />
                      </ItemGroup>
                    </Project>
                    """),
                ("src/Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageVersion Include="Package1" Version="1.0.0" />
                        <PackageVersion Include="Package2" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedResult: new()
            {
                Path = "src",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        TargetFrameworks = ["net9.0"],
                        Dependencies = [
                            new("Package1", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"], IsDirect: true),
                            new("Package2", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"], IsDirect: true),
                        ],
                        Properties = [
                            new("MSBuildTreatWarningsAsErrors", "false", "src/project.csproj"), // this was specifically overridden by discovery
                            new("TargetFramework", "net9.0", "src/project.csproj"),
                            new("TreatWarningsAsErrors", "false", "src/project.csproj"), // this was specifically overridden by discovery
                        ],
                        ReferencedProjectPaths = [],
                        ImportedFiles = ["Directory.Packages.props"],
                        AdditionalFiles = [],
                    }
                ]
            }
        );
    }
}
