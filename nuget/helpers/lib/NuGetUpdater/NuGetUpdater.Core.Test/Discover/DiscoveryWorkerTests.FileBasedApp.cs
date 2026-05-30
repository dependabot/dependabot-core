using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class FileBasedApps : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversCSharpFileBasedAppPackageDirectives()
        {
            await TestDiscoveryAsync(
                workspacePath: "",
                files:
                [
                    ("app.cs", """
                        #:package Humanizer@2.14.1
                        #:package Microsoft.Extensions.Configuration@*
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
                                new("Humanizer", "2.14.1", DependencyType.PackageReference, TargetFrameworks: ["net10.0"]),
                                new("Microsoft.Extensions.Configuration", "*", DependencyType.PackageReference, TargetFrameworks: ["net10.0"]),
                                new("Newtonsoft.Json", null, DependencyType.PackageReference, TargetFrameworks: ["net10.0"]),
                            ],
                            TargetFrameworks = ["net10.0"],
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
                                new("Discovered.Package", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net10.0"]),
                            ],
                            TargetFrameworks = ["net10.0"],
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
                            TargetFrameworks = ["net10.0"],
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
    }
}
