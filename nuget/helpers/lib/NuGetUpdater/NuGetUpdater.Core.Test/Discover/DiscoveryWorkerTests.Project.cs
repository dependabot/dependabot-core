using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class Projects : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task TargetFrameworksAreHonoredInConditions_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net7.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                          </PropertyGroup>
                          <ItemGroup Condition=" '$(TargetFramework)' == 'net7.0' ">
                            <PackageReference Include="Package.A" />
                            <PackageReference Include="Package.B" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Package.A" Version="1.0.0" />
                            <PackageVersion Include="Package.B" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Package.A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                                new("Package.B", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFrameworks", "net7.0;net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net7.0"], // net8.0 has no packages and is not reported
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.props",
                                "Directory.Packages.props",
                            ],
                            AdditionalFiles = [],
                        },
                    ],
                }
            );
        }

        [Fact]
        public async Task TargetFrameworksAreHonoredInConditions_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net7.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                          </PropertyGroup>
                          <ItemGroup Condition=" '$(TargetFramework)' == 'net7.0' ">
                            <PackageReference Include="Package.A" />
                            <PackageReference Include="Package.B" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Package.A" Version="1.0.0" />
                            <PackageVersion Include="Package.B" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Package.A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net7.0", "net8.0"], IsDirect: true),
                                new("Package.B", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net7.0", "net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("ManagePackageVersionsCentrally", "true", "Directory.Packages.props"),
                                new("TargetFrameworks", "net7.0;net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net7.0", "net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.props",
                                "Directory.Packages.props",
                            ],
                            AdditionalFiles = [],
                        },
                    ],
                }
            );
        }

        [Fact]
        public async Task WithDirectoryBuildPropsAndTargets_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net8.0"),
                ],
                workspacePath: "",
                files: [
                    ("project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net8.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.targets", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <ItemGroup>
                            <PackageReference Include="Package.B" Version="4.5.6">
                              <PrivateAssets>all</PrivateAssets>
                              <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
                            </PackageReference>
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("ImplicitUsings", "enable", "project.csproj"),
                                new("Nullable", "enable", "project.csproj"),
                                new("OutputType", "Exe", "project.csproj"),
                                new("TargetFramework", "net8.0", "project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.props",
                                "Directory.Build.targets",
                            ],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task WithDirectoryBuildPropsAndTargets_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net8.0"),
                ],
                workspacePath: "",
                files: [
                    ("project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <OutputType>Exe</OutputType>
                            <TargetFramework>net8.0</TargetFramework>
                            <ImplicitUsings>enable</ImplicitUsings>
                            <Nullable>enable</Nullable>
                          </PropertyGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.targets", """
                        <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <ItemGroup>
                            <PackageReference Include="Package.B" Version="4.5.6">
                              <PrivateAssets>all</PrivateAssets>
                              <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
                            </PackageReference>
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            Properties = [
                                new("ImplicitUsings", "enable", "project.csproj"),
                                new("Nullable", "enable", "project.csproj"),
                                new("OutputType", "Exe", "project.csproj"),
                                new("TargetFramework", "net8.0", "project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.props",
                                "Directory.Build.targets"
                            ],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task WithGlobalPackageReference_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Global.Package", "1.2.3", "net8.0"),
                ],
                workspacePath: "",
                files:
                [
                    ("project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                        </Project>
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <ItemGroup>
                            <GlobalPackageReference Include="Global.Package" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Global.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("ManagePackageVersionsCentrally", "true", "project.csproj"),
                                new("TargetFramework", "net8.0", "project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Packages.props"
                            ],
                            AdditionalFiles = [],
                        },
                    ],
                }
            );
        }

        [Fact]
        public async Task WithGlobalPackageReference_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Global.Package", "1.2.3", "net8.0"),
                ],
                workspacePath: "",
                files:
                [
                    ("project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                        </Project>
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <ItemGroup>
                            <GlobalPackageReference Include="Global.Package" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Global.Package", "1.2.3", DependencyType.GlobalPackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            Properties = [
                                new("ManagePackageVersionsCentrally", "true", "project.csproj"),
                                new("TargetFramework", "net8.0", "project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Packages.props"
                            ],
                            AdditionalFiles = [],
                        },
                    ],
                }
            );
        }

        [Fact]
        public async Task WithPackagesProps_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CentralPackageVersionsPackage,
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Global.Package", "7.8.9", "net7.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net7.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                            <PackageReference Include="Package.B" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Packages.props", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <ItemGroup>
                            <GlobalPackageReference Include="Global.Package" Version="7.8.9" />
                            <PackageReference Update="@(GlobalPackageReference)" PrivateAssets="Build" />
                            <PackageReference Update="Package.B" Version="4.5.6" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.targets", """
                        <Project>
                          <!-- this forces `Packages.props` to be imported -->
                          <Sdk Name="Microsoft.Build.CentralPackageVersions" Version="2.1.3" />
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                                new("Global.Package", "7.8.9", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net7.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net7.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.targets",
                                "Packages.props",
                            ],
                            AdditionalFiles = [],
                        },
                    ],
                }
            );
        }

        [Fact]
        public async Task WithPackagesProps_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CentralPackageVersionsPackage,
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Global.Package", "7.8.9", "net7.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net7.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                            <PackageReference Include="Package.B" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Packages.props", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <ItemGroup>
                            <GlobalPackageReference Include="Global.Package" Version="7.8.9" />
                            <PackageReference Update="@(GlobalPackageReference)" PrivateAssets="Build" />
                            <PackageReference Update="Package.B" Version="4.5.6" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.targets", """
                        <Project>
                          <!-- this forces `Packages.props` to be imported -->
                          <Sdk Name="Microsoft.Build.CentralPackageVersions" Version="2.1.3" />
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            ExpectedDependencyCount = 4,
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                                new("Global.Package", "7.8.9", DependencyType.GlobalPackageReference, TargetFrameworks: ["net7.0"]),
                            ],
                            Properties = [
                                new("TargetFramework", "net7.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net7.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.targets",
                                "Packages.props",
                            ],
                            AdditionalFiles = [],
                        },
                    ],
                }
            );
        }

        [Fact]
        public async Task ReturnsDependenciesThatCannotBeEvaluated_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net8.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                            <PackageReference Include="Package.B" Version="$(ThisPropertyCannotBeResolved)" />
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
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task ReturnsDependenciesThatCannotBeEvaluated_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net8.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                            <PackageReference Include="Package.B" Version="$(ThisPropertyCannotBeResolved)" />
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
                            FilePath = "myproj.csproj",
                            ExpectedDependencyCount = 2,
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task TargetFrameworkCanBeResolvedFromImplicitlyImportedFile_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>$(SomeTfm)</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <PropertyGroup>
                            <SomeTfm>net8.0</SomeTfm>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.props"
                            ],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task TargetFrameworkCanBeResolvedFromImplicitlyImportedFile_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>$(SomeTfm)</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <PropertyGroup>
                            <SomeTfm>net8.0</SomeTfm>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("SomeTfm", "net8.0", "Directory.Build.props"),
                                new("TargetFramework", "$(SomeTfm)", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [
                                "Directory.Build.props"
                            ],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]

        public async Task NoDependenciesReturnedIfNoTargetFrameworkCanBeResolved(bool useDirectDiscovery)
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
                packages: [],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>$(SomeCommonTfmThatCannotBeResolved)</TargetFramework>
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
                    Projects = []
                }
            );
        }

        [Fact]
        public async Task WildcardVersionNumberIsResolved()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
                ],
                workspacePath: "",
                files: [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.*" />
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
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task DiscoverReportsTransitivePackageVersionsWithFourPartsForMultipleTargetFrameworks_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    new("Some.Package", "1.2.3.4", Files: [("lib/net7.0/Some.Package.dll", Array.Empty<byte>()), ("lib/net8.0/Some.Package.dll", Array.Empty<byte>())], DependencyGroups: [(null, [("Transitive.Dependency", "5.6.7.8")])]),
                    new("Transitive.Dependency", "5.6.7.8", Files: [("lib/net7.0/Transitive.Dependency.dll", Array.Empty<byte>()), ("lib/net8.0/Transitive.Dependency.dll", Array.Empty<byte>())]),
                ],
                workspacePath: "",
                files:
                [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.2.3.4" />
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
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Some.Package", "1.2.3.4", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                                new("Some.Package", "1.2.3.4", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                                new("Transitive.Dependency", "5.6.7.8", DependencyType.Unknown, TargetFrameworks: ["net7.0"], IsTransitive: true),
                                new("Transitive.Dependency", "5.6.7.8", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
                            ],
                            Properties = [
                                new("TargetFrameworks", "net7.0;net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net7.0", "net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task DiscoverReportsTransitivePackageVersionsWithFourPartsForMultipleTargetFrameworks_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    new("Some.Package", "1.2.3.4", Files: [("lib/net7.0/Some.Package.dll", Array.Empty<byte>()), ("lib/net8.0/Some.Package.dll", Array.Empty<byte>())], DependencyGroups: [(null, [("Transitive.Dependency", "5.6.7.8")])]),
                    new("Transitive.Dependency", "5.6.7.8", Files: [("lib/net7.0/Transitive.Dependency.dll", Array.Empty<byte>()), ("lib/net8.0/Transitive.Dependency.dll", Array.Empty<byte>())]),
                ],
                workspacePath: "",
                files:
                [
                    ("myproj.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.2.3.4" />
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
                            FilePath = "myproj.csproj",
                            Dependencies = [
                                new("Some.Package", "1.2.3.4", DependencyType.PackageReference, TargetFrameworks: ["net7.0", "net8.0"], IsDirect: true),
                                new("Transitive.Dependency", "5.6.7.8", DependencyType.Unknown, TargetFrameworks: ["net7.0", "net8.0"], IsTransitive: true),
                            ],
                            Properties = [
                                new("TargetFrameworks", "net7.0;net8.0", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net7.0", "net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task DiscoverReportsPackagesThroughProjectReferenceElements_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net8.0"),
                ],
                workspacePath: "test",
                files:
                [
                    ("test/unit-tests.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <ProjectReference Include="..\src\helpers.csproj" />
                          </ItemGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("src/helpers.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.B" Version="4.5.6" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "test",
                    Projects = [
                        new()
                        {
                            FilePath = "unit-tests.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                                new("Package.B", "4.5.6", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true)
                            ],
                            ReferencedProjectPaths = [
                                "../src/helpers.csproj",
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", @"test/unit-tests.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                        new()
                        {
                            FilePath = "../src/helpers.csproj",
                            Dependencies = [
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", @"src/helpers.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task DiscoverReportsPackagesThroughProjectReferenceElements_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.2.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "4.5.6", "net8.0"),
                ],
                workspacePath: "test",
                files:
                [
                    ("test/unit-tests.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <ProjectReference Include="..\src\helpers.csproj" />
                          </ItemGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.A" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("src/helpers.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Package.B" Version="4.5.6" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "test",
                    Projects = [
                        new()
                        {
                            FilePath = "unit-tests.csproj",
                            Dependencies = [
                                new("Package.A", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                            ],
                            ReferencedProjectPaths = [
                                "../src/helpers.csproj",
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", @"test/unit-tests.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                        new()
                        {
                            FilePath = "../src/helpers.csproj",
                            Dependencies = [
                                new("Package.B", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", @"src/helpers.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task DiscoverReportsPackagesThroughSolutionFilesNotInTheSameDirectoryTreeAsTheProjects()
        {
            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
                ],
                workspacePath: "solutions",
                files:
                [
                    ("solutions/sln.sln", """
                        Microsoft Visual Studio Solution File, Format Version 12.00
                        # Visual Studio Version 17
                        VisualStudioVersion = 17.5.33516.290
                        MinimumVisualStudioVersion = 10.0.40219.1
                        Project("{9A19103F-16F7-4668-BE54-9A1E7A4F7556}") = "library", "..\projects\library.csproj", "{DA55A30A-048A-4D8A-A3EC-4F2CF4B294B8}"
                        EndProject
                        Global
                        	GlobalSection(SolutionConfigurationPlatforms) = preSolution
                        		Debug|Any CPU = Debug|Any CPU
                        		Release|Any CPU = Release|Any CPU
                        	EndGlobalSection
                        	GlobalSection(ProjectConfigurationPlatforms) = postSolution
                        		{DA55A30A-048A-4D8A-A3EC-4F2CF4B294B8}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
                        		{DA55A30A-048A-4D8A-A3EC-4F2CF4B294B8}.Debug|Any CPU.Build.0 = Debug|Any CPU
                        		{DA55A30A-048A-4D8A-A3EC-4F2CF4B294B8}.Release|Any CPU.ActiveCfg = Release|Any CPU
                        		{DA55A30A-048A-4D8A-A3EC-4F2CF4B294B8}.Release|Any CPU.Build.0 = Release|Any CPU
                        	EndGlobalSection
                        EndGlobal
                        """),
                    ("projects/library.csproj", """
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
                    Path = "solutions",
                    Projects = [
                        new()
                        {
                            FilePath = "../projects/library.csproj",
                            Dependencies = [
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", @"projects/library.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task DiscoveryWithTargetPlaformVersion_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
                ],
                workspacePath: "src",
                files:
                [
                    ("src/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFrameworks>net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst</TargetFrameworks>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0-android"], IsDirect: true),
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0-ios"], IsDirect: true),
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0-maccatalyst"], IsDirect: true),
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0-macos"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFrameworks", "net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst", @"src/project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0-android", "net8.0-ios", "net8.0-maccatalyst", "net8.0-macos"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task DiscoveryWithTargetPlaformVersion_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
                ],
                workspacePath: "src",
                files:
                [
                    ("src/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFrameworks>net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst</TargetFrameworks>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0-android", "net8.0-ios", "net8.0-maccatalyst", "net8.0-macos"], IsDirect: true)
                            ],
                            Properties = [
                                new("TargetFrameworks", "net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst", @"src/project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0-android", "net8.0-ios", "net8.0-maccatalyst", "net8.0-macos"],
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
        public async Task PackageLockJsonFileIsReported(bool useDirectDiscovery)
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3", "net8.0"),
                ],
                workspacePath: "src",
                files:
                [
                    ("src/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.2.3" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("src/packages.lock.json", """
                        {}
                        """),
                ],
                expectedResult: new()
                {
                    Path = "src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                            ],
                            Properties = [
                                new("TargetFramework", "net8.0", "src/project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [
                                "packages.lock.json"
                            ],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task PackagesManagedAndRemovedByTheSdkAreReported()
        {
            // To avoid a unit test that's tightly coupled to the installed SDK, some files are faked.
            // First up, the `dotnet-package-correlation.json` is faked to have the appropriate shape to report a
            // package replacement.  Doing this requires a temporary file and environment variable override.
            using var tempDirectory = new TemporaryDirectory();
            var packageCorrelationFile = Path.Combine(tempDirectory.DirectoryPath, "dotnet-package-correlation.json");
            await File.WriteAllTextAsync(packageCorrelationFile, """
                {
                    "Sdks": {
                        "8.0.100": {
                            "Packages": {
                                "Test.Only.Package": "1.0.99"
                            }
                        }
                    }
                }
                """);
            using var tempEnvironment = new TemporaryEnvironment([("DOTNET_PACKAGE_CORRELATION_FILE_PATH", packageCorrelationFile)]);

            // The SDK package handling is detected in a very specific circumstance; an assembly being removed from the
            // `@(RuntimeCopyLocalItems)` item group in the `GenerateBuildDependencyFile` target.  Since we don't want
            // to involve the real SDK, we fake some required targets.
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { InstallDotnetSdks = true, UseDirectDiscovery = true },
                packages: [],
                workspacePath: "",
                files:
                [
                    ("project.csproj", """
                        <Project>
                          <!-- note that the attribute `Sdk="Microsoft.NET.Sdk"` is missing because we don't want the real SDK interfering. -->

                          <!-- This allows the detection custom targets to be injected. -->
                          <Import Project="$(CustomAfterMicrosoftCommonTargets)" Condition="Exists('$(CustomAfterMicrosoftCommonTargets)')" />

                          <PropertyGroup>
                            <!-- This property is used for the package lookup from the correlation file. -->
                            <NETCoreSdkVersion>8.0.100</NETCoreSdkVersion>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <Target Name="_TEST_ONLY_POPULATE_GROUP_">
                            <ItemGroup>
                              <!-- We first need a value in this item group with the approprate metadata to simulate it having been added by NuGet. -->
                              <RuntimeCopyLocalItems Include="TestOnlyAssembly.dll" NuGetPackageId="Test.Only.Package" NuGetPackageVersion="1.0.0" />
                            </ItemGroup>
                          </Target>

                          <Target Name="GenerateBuildDependencyFile" DependsOnTargets="_TEST_ONLY_POPULATE_GROUP_">
                            <!-- this target needs to exist for discovery to work -->
                            <ItemGroup>
                              <!-- This removal is what triggers the package lookup in the correlation file. -->
                              <RuntimeCopyLocalItems Remove="TestOnlyAssembly.dll" />
                            </ItemGroup>
                          </Target>

                          <Target Name="ResolvePackageAssets">
                            <!-- this target needs to exist for discovery to work -->
                          </Target>
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
                            Dependencies = [
                                new("Test.Only.Package", "1.0.99", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true)
                            ],
                            Properties = [
                                new("NETCoreSdkVersion", "8.0.100", "project.csproj"),
                                new("TargetFramework", "net8.0", "project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }
    }
}
