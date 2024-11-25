using System.Collections.Immutable;
using System.Runtime.InteropServices;
using System.Text.Json;

using NuGetUpdater.Core.Discover;

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

    [Fact]
    public async Task ResultFileHasCorrectShapeForAuthenticationFailure()
    {
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync([]);
        var discoveryResultPath = Path.Combine(temporaryDirectory.DirectoryPath, DiscoveryWorker.DiscoveryResultFileName);
        await DiscoveryWorker.WriteResultsAsync(temporaryDirectory.DirectoryPath, discoveryResultPath, new()
        {
            ErrorType = ErrorType.AuthenticationFailure,
            ErrorDetails = "<some package feed>",
            Path = "/",
            Projects = [],
        });
        var discoveryContents = await File.ReadAllTextAsync(discoveryResultPath);

        // raw result file should look like this:
        // {
        //   ...
        //   "ErrorType": "AuthenticationFailure",
        //   "ErrorDetails": "<some package feed>",
        //   ...
        // }
        var jsonDocument = JsonDocument.Parse(discoveryContents);
        var errorType = jsonDocument.RootElement.GetProperty("ErrorType");
        var errorDetails = jsonDocument.RootElement.GetProperty("ErrorDetails");

        Assert.Equal("AuthenticationFailure", errorType.GetString());
        Assert.Equal("<some package feed>", errorDetails.GetString());
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
                ErrorType = ErrorType.AuthenticationFailure,
                ErrorDetails = $"({http.BaseUrl.TrimEnd('/')}/index.json)",
                Path = "",
                Projects = [],
            }
        );
    }
}
