using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class Projects : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task TargetFrameworksAreHonoredInConditions()
        {
            await TestDiscoveryAsync(
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
        public async Task WithDirectoryBuildPropsAndTargets()
        {
            await TestDiscoveryAsync(
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
        public async Task WithGlobalPackageReference()
        {
            await TestDiscoveryAsync(
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
        public async Task WithPackagesProps()
        {
            await TestDiscoveryAsync(
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
        public async Task ReturnsDependenciesThatCannotBeEvaluated()
        {
            await TestDiscoveryAsync(
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
        public async Task TargetFrameworkCanBeResolvedFromImplicitlyImportedFile()
        {
            await TestDiscoveryAsync(
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
        public async Task NoDependenciesReturnedIfNoTargetFrameworkCanBeResolved()
        {
            await TestDiscoveryAsync(
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
        public async Task DiscoverReportsTransitivePackageVersionsWithFourPartsForMultipleTargetFrameworks()
        {
            await TestDiscoveryAsync(
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
        public async Task DiscoverReportsPackagesThroughProjectReferenceElements()
        {
            await TestDiscoveryAsync(
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
        public async Task WindowsSpecificProjectAndWindowsSpecificDependency()
        {
            await TestDiscoveryAsync(
                packages: [
                    MockNuGetPackage.CreateSimplePackage("Some.Os.Package", "1.2.3", "net6.0-windows7.0")
                ],
                workspacePath: "",
                files: [
                    ("project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net9.0-windows</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Os.Package" Version="1.2.3" />
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
                            Dependencies = [
                                new("Some.Os.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net9.0-windows"], IsDirect: true)
                            ],
                            Properties = [
                                new("TargetFramework", "net9.0-windows", "project.csproj")
                            ],
                            TargetFrameworks = ["net9.0-windows"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = []
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task DiscoveryWithTargetPlaformVersion()
        {
            await TestDiscoveryAsync(
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
                            <TargetFrameworks>net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst;net8.0-windows</TargetFrameworks>
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
                                new("Some.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0-android", "net8.0-ios", "net8.0-maccatalyst", "net8.0-macos", "net8.0-windows"], IsDirect: true),
                            ],
                            Properties = [
                                new("TargetFrameworks", "net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst;net8.0-windows", @"src/project.csproj"),
                            ],
                            TargetFrameworks = ["net8.0-android", "net8.0-ios", "net8.0-maccatalyst", "net8.0-macos", "net8.0-windows"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ]
                }
            );
        }

        [Fact]
        public async Task PackageLockJsonFileIsReported()
        {
            await TestDiscoveryAsync(
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
                    "Runtimes": {
                        "1.0.0": {
                            "Packages": {
                                "Dependabot.App.Core.Ref": "1.0.0",
                                "Test.Only.Package": "1.0.0"
                            }
                        },
                        "1.0.1": {
                            "Packages": {
                                "Dependabot.App.Core.Ref": "1.0.1",
                                "Test.Only.Package": "1.0.99"
                            }
                        }
                    }
                }
                """, TestContext.Current.CancellationToken);
            using var tempEnvironment = new TemporaryEnvironment([("DOTNET_PACKAGE_CORRELATION_FILE_PATH", packageCorrelationFile)]);

            // The SDK package handling is detected in a very specific circumstance; an assembly being removed from the
            // `@(References)` item group in the `_HandlePackageFileConflicts` target.  Since we don't want to involve
            // the real SDK, we fake some required targets.
            await TestDiscoveryAsync(
                packages: [],
                workspacePath: "",
                files:
                [
                    ("project.csproj", """
                        <Project>
                          <!-- note that the attribute `Sdk="Microsoft.NET.Sdk"` is missing because we don't want the real SDK interfering -->

                          <!-- this allows custom targets to be injected for dependency detection -->
                          <Import Project="$(CustomAfterMicrosoftCommonTargets)" Condition="Exists('$(CustomAfterMicrosoftCommonTargets)')" />

                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                            <!-- the SDK turns `<TargetFramework>net8.0</TargetFramework>` into the following -->
                            <TargetFrameworkMoniker>.NETCoreApp,Version=8.0</TargetFrameworkMoniker>
                          </PropertyGroup>

                          <ItemGroup>
                            <!-- we need a value in this item group with the appropriate metadata to simulate it having been added by NuGet -->
                            <RuntimeCopyLocalItems Include="TestOnlyAssembly.dll" NuGetPackageId="Test.Only.Package" NuGetPackageVersion="1.0.0" />

                            <!-- this represents the assemblies being extracted from the package -->
                            <Reference Include="@(RuntimeCopyLocalItems)" />
                          </ItemGroup>

                          <Target Name="_HandlePackageFileConflicts">
                            <!-- this target needs to exist for discovery to work -->
                            <ItemGroup>
                              <!-- this removal is what triggers the package lookup in the correlation file -->
                              <Reference Remove="TestOnlyAssembly.dll" />

                              <!-- this addition is what's used for the lookup -->
                              <Reference Include="TestOnlyAssembly.dll" NuGetPackageId="Dependabot.App.Core.Ref" NuGetPackageVersion="1.0.1" />
                            </ItemGroup>
                          </Target>

                          <Target Name="ResolveAssemblyReferences" DependsOnTargets="_HandlePackageFileConflicts">
                            <!-- this target needs to exist for discovery to work -->
                          </Target>

                          <Target Name="GenerateBuildDependencyFile">
                            <!-- this target needs to exist for discovery to work -->
                            <ItemGroup>
                              <!-- this removal is what removes the regular package reference from the project -->
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
                                new("TargetFramework", "net8.0", "project.csproj"),
                                new("TargetFrameworkMoniker", ".NETCoreApp,Version=8.0", "project.csproj"),
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
        public async Task LegacyProjectWithPackageReferencesReportsDependencies()
        {
            // This is a feature of the VS project system - a legacy project with <PackageReference> elements.  The `dotnet` CLI
            // can't resolve the transitive dependencies; only the VS project system can, so there are some manual steps to allow
            // dependency discovery.
            await TestDiscoveryAsync(
                packages: [
                    MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net48", [(null, [("Some.Transitive.Dependency", "2.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "2.0.0", "net48"),
                ],
                workspacePath: "",
                files: [
                    ("project.csproj", """
                        <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                          <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                          <PropertyGroup>
                            <OutputType>Library</OutputType>
                            <TargetFrameworkVersion>v4.8</TargetFrameworkVersion>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Dependency" Version="1.0.0" />
                          </ItemGroup>
                          <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
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
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net48"], IsDirect: true),
                                new("Some.Transitive.Dependency", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net48"], IsTransitive: true),
                            ],
                            Properties = [],
                            TargetFrameworks = ["net48"],
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
