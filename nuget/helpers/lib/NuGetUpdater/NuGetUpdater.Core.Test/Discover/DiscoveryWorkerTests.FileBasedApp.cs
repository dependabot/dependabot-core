using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class FileBasedApps : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversCSharpFileBasedAppPackageDirectives()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:sdk Microsoft.NET.Sdk
                        #:package Humanizer@2.14.1
                        #:package Microsoft.Extensions.Configuration@* PrivateAssets=all
                        #:package Newtonsoft.Json

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
                                new("Humanizer", "2.14.1", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                                new("Microsoft.Extensions.Configuration", "*", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                                new("Newtonsoft.Json", null, DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                            ],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                    ],
                });
        }

        [Fact]
        public async Task IgnoresPackageDirectivesAfterCSharpCode()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                workspacePath: "",
                files:
                [
                    ("app.cs", """"
                        #:package Real.Package@1.0.0

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
                                new("Real.Package", "1.0.0", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                            ],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                    ],
                });
        }

        [Fact]
        public async Task IgnoresCSharpFilesUnderCSharpProjectCones()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
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
                    ("tools/app.cs", "#:package Discovered.Package@2.0.0"),
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects =
                    [
                        new()
                        {
                            FilePath = "tools/app.cs",
                            Dependencies =
                            [
                                new("Discovered.Package", "2.0.0", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                            ],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                    ],
                });
        }

        [Fact]
        public async Task IgnoresCSharpFilesWhenWorkspaceIsInsideCSharpProjectCone()
        {
            await TestDiscoveryAsync(
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
                });
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
                });
        }

        [Fact]
        public async Task SkipsCSharpFileBasedAppsWhenDisabled()
        {
            await TestDiscoveryAsync(
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
                experimentsManager: new() { UpdateFileBasedApps = false });
        }

        [Fact]
        public async Task DiscoversCSharpFileBasedAppPackageLockFile()
        {
            var targetFramework = await GetFileBasedAppDefaultTargetFrameworkAsync();

            await TestDiscoveryAsync(
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:property RestorePackagesWithLockFile=true
                        #:package Humanizer@2.14.1

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
                                new("Humanizer", "2.14.1", DependencyType.PackageReference, TargetFrameworks: [targetFramework]),
                            ],
                            TargetFrameworks = [targetFramework],
                            ReferencedProjectPaths = [],
                            ImportedFiles = [],
                            AdditionalFiles = ["packages.lock.json"],
                        },
                    ],
                });
        }

        private static async Task<string> GetFileBasedAppDefaultTargetFrameworkAsync()
        {
            using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync();
            return await CSharpFileBasedAppDiscovery.GetDefaultTargetFrameworkAsync(tempDirectory.DirectoryPath, new TestLogger());
        }
    }
}
