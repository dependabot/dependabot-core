using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class FileBasedApps : DiscoveryWorkerTestBase
    {
        private static readonly ExperimentsManager FileBasedAppsEnabled = new() { UpdateFileBasedApps = true };

        [Fact]
        public async Task DiscoversResolvedCSharpFileBasedAppDependencies()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage(
                        "FileApp.TopLevel.Package",
                        "1.0.0",
                        targetFramework,
                        [(null, [("FileApp.Transitive.Package", "2.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("FileApp.Transitive.Package", "2.0.0", targetFramework),
                    MockNuGetPackage.CreateSimplePackage("FileApp.Floating.Package", "1.0.0", targetFramework),
                    MockNuGetPackage.CreateSimplePackage("FileApp.Floating.Package", "2.0.0", targetFramework),
                    MockNuGetPackage.CreateSimplePackage("FileApp.Versionless.Package", "3.0.0", targetFramework),
                    MockNuGetPackage.CreateSimplePackage("FileApp.Versionless.Package", "4.0.0", targetFramework),
                ],
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:sdk Microsoft.NET.Sdk
                        #:package FileApp.TopLevel.Package
                        #:package FileApp.Floating.Package PrivateAssets=all
                        #:package FileApp.Versionless.Package

                        Console.WriteLine("Hello");
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageFloatingVersionsEnabled>true</CentralPackageFloatingVersionsEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="FileApp.TopLevel.Package" Version="1.0.0" />
                            <PackageVersion Include="FileApp.Floating.Package" Version="*" />
                            <PackageVersion Include="FileApp.Versionless.Package" Version="3.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "app.cs",
                            Dependencies =
                            [
                                new("FileApp.Floating.Package", "2.0.0", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                                new("FileApp.TopLevel.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                                new("FileApp.Transitive.Package", "2.0.0", DependencyType.Unknown, TargetFrameworks: [targetFramework], IsTopLevel: false),
                                new("FileApp.Versionless.Package", "3.0.0", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                            ],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = ["Directory.Packages.props"],
                            AdditionalFiles = [],
                            ExpectedPackageManagementKind = PackageManagementKind.CentralPackageManagement,
                            ExpectedPackageManagementSpecialFileRelativePath = "Directory.Packages.props",
                            ExpectedDependencyGraph = new Dictionary<string, string[]>
                            {
                                ["FileApp.Floating.Package/2.0.0"] = [],
                                ["FileApp.TopLevel.Package/1.0.0"] = ["FileApp.Transitive.Package/2.0.0"],
                                ["FileApp.Transitive.Package/2.0.0"] = [],
                                ["FileApp.Versionless.Package/3.0.0"] = [],
                            }.ToImmutableDictionary(
                                kvp => kvp.Key,
                                kvp => kvp.Value.ToImmutableArray(),
                                StringComparer.OrdinalIgnoreCase),
                        },
                    ],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Fact]
        public async Task ReportsVersionlessPackageWithoutCentralPackageManagement()
        {
            await TestDiscoveryAsync(
                packages: [MockNuGetPackage.CreateSimplePackage("FileApp.Unconfigured.Package", "1.0.0", "net8.0")],
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:property TargetFramework=net8.0
                        #:package FileApp.Unconfigured.Package
                        Console.WriteLine();
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [],
                    IsSuccess = false,
                    ErrorRegex = "NU1015",
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Theory]
        [InlineData("")]
        [InlineData("tools")]
        public async Task DiscoversVersionlessPackageFromCentralPackageManagement(string workspacePath)
        {
            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("FileApp.Central.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("FileApp.Central.Package", "2.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("FileApp.Central.Package", "3.0.0", "net8.0"),
                ],
                workspacePath: workspacePath,
                files:
                [
                    ("tools/app.cs", """
                        #:property TargetFramework=net8.0
                        #:package FileApp.Central.Package

                        Console.WriteLine("Hello");
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <Import Project="versions.props" />
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="FileApp.Central.Package" Version="$(FileAppVersion)" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("versions.props", """
                        <Project>
                          <PropertyGroup>
                            <FileAppVersion>2.0.0</FileAppVersion>
                          </PropertyGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    Path = workspacePath,
                    Projects =
                    [
                        new()
                        {
                            FilePath = workspacePath.Length == 0 ? "tools/app.cs" : "app.cs",
                            Dependencies =
                            [
                                new("FileApp.Central.Package", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = ["../Directory.Packages.props", "../versions.props"],
                            AdditionalFiles = [],
                            ExpectedPackageManagementKind = PackageManagementKind.CentralPackageManagement,
                            ExpectedPackageManagementSpecialFileRelativePath = "../Directory.Packages.props",
                        },
                    ],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Fact]
        public async Task DiscoversCSharpFileBasedAppTargetFrameworkProperty()
        {
            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("FileApp.TargetFramework.Package", "1.0.0", "net8.0"),
                ],
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:property TargetFramework=net8.0
                        #:package FileApp.TargetFramework.Package@1.0.0

                        Console.WriteLine("Hello");
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "app.cs",
                            Dependencies =
                            [
                                new("FileApp.TargetFramework.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"]),
                            ],
                            TargetFrameworks = ["net8.0"],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                    ],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Fact]
        public async Task IgnoresPackageDirectivesAfterCSharpCode()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("FileApp.Real.Package", "1.0.0", targetFramework),
                    MockNuGetPackage.CreateSimplePackage("Phantom.Package", "9.9.9", targetFramework),
                ],
                workspacePath: "",
                files:
                [
                    ("app.cs", """"
                        #:package FileApp.Real.Package@1.0.0

                        var text = """
                        #:package Phantom.Package@9.9.9
                        """;
                        """"),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "app.cs",
                            Dependencies =
                            [
                                new("FileApp.Real.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                            ],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                    ],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Fact]
        public async Task IgnoresCSharpFilesUnderCSharpProjectCones()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Ignored.Package", "1.0.0", targetFramework),
                    MockNuGetPackage.CreateSimplePackage("Also.Ignored", "1.0.0", targetFramework),
                ],
                workspacePath: "",
                files:
                [
                    ("src/project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                        </Project>
                        """),
                    ("src/app.cs", "#:package Ignored.Package@1.0.0"),
                    ("src/subdir/also-ignored.cs", "#:package Also.Ignored@1.0.0"),
                    ("tools/app.cs", "#!/usr/bin/env dotnet run\nConsole.WriteLine();"),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "tools/app.cs",
                            Dependencies = [],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                    ],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Fact]
        public async Task IgnoresCSharpFilesWhenWorkspaceIsInsideCSharpProjectCone()
        {
            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Ignored.Package", "1.0.0", "net8.0"),
                ],
                workspacePath: "src",
                files:
                [
                    ("project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                        </Project>
                        """),
                    ("src/app.cs", "#:package Ignored.Package@1.0.0"),
                ],
                expectedResult: new()
                {
                    Path = "src",
                    Projects = [],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Fact]
        public async Task DiscoversBomShebangCSharpFileBasedAppWithoutPackages()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                workspacePath: "",
                files:
                [
                    ("app.cs", "\uFEFF#!/usr/bin/env dotnet run\nConsole.WriteLine(\"Hello\");"),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "app.cs",
                            Dependencies = [],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                    ],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        [Fact]
        public async Task SkipsCSharpFileBasedAppsWhenDisabled()
        {
            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Humanizer", "2.14.1", "net8.0"),
                ],
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:package Humanizer@2.14.1

                        Console.WriteLine("Hello");
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [],
                },
                experimentsManager: new ExperimentsManager());
        }

        [Fact]
        public async Task DiscoversCSharpFileBasedAppPackageLockFile()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("FileApp.Locked.Package", "2.14.1", targetFramework),
                ],
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:property RestorePackagesWithLockFile=true
                        #:package FileApp.Locked.Package@2.14.1

                        Console.WriteLine("Hello");
                        """),
                    ("packages.lock.json", "{}"),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "app.cs",
                            Dependencies =
                            [
                                new("FileApp.Locked.Package", "2.14.1", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                            ],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = ["packages.lock.json"],
                        },
                    ],
                },
                experimentsManager: FileBasedAppsEnabled);
        }

        private static async Task<string> GetFileBasedAppDefaultTargetFrameworkAsync()
        {
            using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync();
            return await CSharpFileBasedAppDiscovery.GetDefaultTargetFrameworkAsync(tempDirectory.DirectoryPath, new TestLogger());
        }
    }
}
