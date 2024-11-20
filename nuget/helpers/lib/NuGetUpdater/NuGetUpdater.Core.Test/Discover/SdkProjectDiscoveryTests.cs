using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Update;

using Xunit;

using TestFile = (string Path, string Content);

namespace NuGetUpdater.Core.Test.Discover;

public class SdkProjectDiscoveryTests : DiscoveryWorkerTestBase
{
    [Fact]
    public async Task DiscoveryInSingleProject_TopLevelAndTransitive()
    {
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Top.Level.Package", "1.2.3", "net8.0", [("net8.0", [("Transitive.Dependency", "4.5.6")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "4.5.6", "net8.0"),
            ],
            startingDirectory: "src",
            projectPath: "src/library.csproj",
            files:
            [
                ("src/library.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Top.Level.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library.csproj",
                    Dependencies =
                    [
                        new("Top.Level.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        new("Transitive.Dependency", "4.5.6", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true)
                    ],
                    ImportedFiles = [],
                    Properties =
                    [
                        new("TargetFramework", "net8.0", "src/library.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                }
            ]
        );
    }

    [Fact]
    public async Task DiscoveryInSingleProject_PackageAddedInTargetsFile()
    {
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Top.Level.Package", "1.2.3", "net8.0", [("net8.0", [("Transitive.Dependency", "4.5.6")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "4.5.6", "net8.0"),
            ],
            startingDirectory: "src",
            projectPath: "src/library.csproj",
            files:
            [
                ("src/library.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """),
                ("Directory.Build.targets", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Top.Level.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library.csproj",
                    Dependencies =
                    [
                        // dependencies come from `Directory.Build.targets`, but it's through the evaluation of `src/library.csproj` that it's found
                        new("Top.Level.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        new("Transitive.Dependency", "4.5.6", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true)
                    ],
                    Properties =
                    [
                        new("TargetFramework", "net8.0", "src/library.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                }
            ]
        );
    }

    [Fact]
    public async Task DiscoveryThroughProjectReference()
    {
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Top.Level.Package", "1.2.3", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Dependency.From.Other.Project", "4.5.6", "net8.0"),
            ],
            startingDirectory: "src/library1",
            projectPath: "src/library1/library1.csproj",
            files:
            [
                ("src/library1/library1.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <ProjectReference Include="../library2/library2.csproj" />
                      </ItemGroup>
                      <ItemGroup>
                        <PackageReference Include="Top.Level.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
                ("src/library2/library2.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Dependency.From.Other.Project" Version="4.5.6" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library1.csproj",
                    Dependencies =
                    [
                        new("Top.Level.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        new("Dependency.From.Other.Project", "4.5.6", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true)
                    ],
                    ImportedFiles = [],
                    ReferencedProjectPaths = [
                        "../library2/library2.csproj"
                    ],
                    Properties =
                    [
                        new("TargetFramework", "net8.0", "src/library1/library1.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                },
                new()
                {
                    FilePath = "../library2/library2.csproj",
                    Dependencies =
                    [
                        new("Dependency.From.Other.Project", "4.5.6", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true)
                    ],
                    Properties =
                    [
                        new("TargetFramework", "net8.0", "src/library2/library2.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                }
            ]
        );
    }

    [Fact]
    public async Task DiscoveryThroughProjectReferenceThroughTransitiveDependency()
    {
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Top.Level.Package", "1.2.3", "net8.0", [("net8.0", [("Transitive.Dependency", "4.5.6")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "4.5.6", "net8.0"),
            ],
            startingDirectory: "src/library1",
            projectPath: "src/library1/library1.csproj",
            files:
            [
                ("src/library1/library1.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <ProjectReference Include="../library2/library2.csproj" />
                      </ItemGroup>
                    </Project>
                    """),
                ("src/library2/library2.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Top.Level.Package" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library1.csproj",
                    Dependencies =
                    [
                        // these are all transitive through the ProjectReference
                        new("Top.Level.Package", "1.2.3", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
                        new("Transitive.Dependency", "4.5.6", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true)
                    ],
                    ImportedFiles = [],
                    ReferencedProjectPaths = [
                        "../library2/library2.csproj",
                    ],
                    Properties =
                    [
                        new("TargetFramework", "net8.0", "src/library1/library1.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                },
                new()
                {
                    FilePath = "../library2/library2.csproj",
                    Dependencies =
                    [
                        new("Top.Level.Package", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                        new("Transitive.Dependency", "4.5.6", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true)
                    ],
                    ImportedFiles = [],
                    Properties =
                    [
                        new("TargetFramework", "net8.0", "src/library2/library2.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                }
            ]
        );
    }

    [Fact]
    public async Task DiscoverWithMultipleTargetFrameworks()
    {
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.2.3", "net7.0"),
            ],
            startingDirectory: "src",
            projectPath: "src/library.csproj",
            files:
            [
                ("src/library.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library.csproj",
                    Dependencies =
                    [
                        new("Some.Dependency", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net7.0"], IsDirect: true),
                        new("Some.Dependency", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                    ],
                    ImportedFiles = [],
                    Properties =
                    [
                        new("TargetFrameworks", "net7.0;net8.0", "src/library.csproj"),
                    ],
                    TargetFrameworks = ["net7.0", "net8.0"]
                },
            ]
        );
    }

    [Fact]
    public async Task DiscoveryIgnoresNetStandardLibrary()
    {
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.2.3", "netstandard2.0"),
            ],
            startingDirectory: "src",
            projectPath: "src/library.csproj",
            files:
            [
                ("src/library.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library.csproj",
                    Dependencies =
                    [
                        new("Some.Dependency", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["netstandard2.0"], IsDirect: true),
                    ],
                    ImportedFiles = [],
                    Properties =
                    [
                        new("TargetFramework", "netstandard2.0", "src/library.csproj"),
                    ],
                    TargetFrameworks = ["netstandard2.0"]
                },
            ]
        );
    }

    [Fact]
    public async Task GlobalPackages()
    {
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.2.3", "netstandard2.0"),
            ],
            startingDirectory: "src",
            projectPath: "src/library.csproj",
            files:
            [
                ("src/library.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                    </Project>
                    """),
                ("src/Directory.Build.props", """
                    <Project>
                      <ItemGroup>
                        <GlobalPackageReference Include="Some.Dependency" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library.csproj",
                    Dependencies =
                    [
                        new("Some.Dependency", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                    ],
                    ImportedFiles =
                    [
                        "Directory.Build.props",
                    ],
                    Properties =
                    [
                        new("ManagePackageVersionsCentrally", "true", "src/library.csproj"),
                        new("TargetFramework", "net8.0", "src/library.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                },
            ]
        );
    }

    [Fact]
    public async Task CentralPackageManagementAlternatePackagesPropsLocation()
    {
        // when using central package management, the well-known file `Directory.Packages.props` can be overridden with
        // the `$(DirectoryPackagesPropsPath)` property
        await TestDiscoverAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.2.3", "netstandard2.0"),
            ],
            startingDirectory: "src",
            projectPath: "src/library.csproj",
            files:
            [
                ("src/library.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("src/Directory.Build.props", """
                    <Project>
                      <PropertyGroup>
                        <DirectoryPackagesPropsPath>$(MSBuildThisFileDirectory)..\NonStandardPackages.props</DirectoryPackagesPropsPath>
                      </PropertyGroup>
                    </Project>
                    """),
                ("NonStandardPackages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.2.3" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedProjects:
            [
                new()
                {
                    FilePath = "library.csproj",
                    Dependencies =
                    [
                        new("Some.Dependency", "1.2.3", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
                    ],
                    ImportedFiles =
                    [
                        "../NonStandardPackages.props",
                        "Directory.Build.props",
                    ],
                    Properties =
                    [
                        new("ManagePackageVersionsCentrally", "true", "src/library.csproj"),
                        new("TargetFramework", "net8.0", "src/library.csproj"),
                    ],
                    TargetFrameworks = ["net8.0"]
                },
            ]
        );
    }

    private static async Task TestDiscoverAsync(string startingDirectory, string projectPath, TestFile[] files, ImmutableArray<ExpectedSdkProjectDiscoveryResult> expectedProjects, MockNuGetPackage[]? packages = null)
    {
        using var testDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);

        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, testDirectory.DirectoryPath);

        var logger = new TestLogger();
        var fullProjectPath = Path.Combine(testDirectory.DirectoryPath, projectPath);
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = true }; // the following method is direct discovery; this just makes the call to Validate... happy
        var projectDiscovery = await SdkProjectDiscovery.DiscoverWithBinLogAsync(testDirectory.DirectoryPath, Path.GetDirectoryName(fullProjectPath)!, fullProjectPath, logger);
        ValidateProjectResults(expectedProjects, projectDiscovery, experimentsManager);
    }
}
