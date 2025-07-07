using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class FileWriterWorkerTests : TestBase
{
    [Fact]
    public async Task EndToEnd_ProjectReference()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="2.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/project.csproj"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_ProjectReferenceWithPackageLockJson()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                ("packages.lock.json", "{}")
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="2.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/project.csproj"] }
            ],
            additionalChecks: (repoContentsPath) =>
            {
                // ensure the lock file was updated; we don't care how, just that it was
                var lockFilePath = Path.Join(repoContentsPath.FullName, "packages.lock.json");
                var lockFileContent = File.ReadAllText(lockFilePath);
                Assert.NotEqual("{}", lockFileContent);
            }
        );
    }

    [Fact]
    public async Task EndToEnd_PackagesConfig()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Dependency">
                      <HintPath>packages\Some.Dependency.1.0.0\lib\net45\Some.Dependency.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            additionalFiles: [
                ("packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Dependency" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net45"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Dependency">
                      <HintPath>packages\Some.Dependency.2.0.0\lib\net45\Some.Dependency.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedAdditionalFiles: [
                ("packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Dependency" version="2.0.0" targetFramework="net45" />
                    </packages>
                    """)
            ],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/project.csproj", "/packages.config"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_DotNetTools()
    {
        // project is unchanged but `.config/dotnet-tools.json` is updated
        await TestAsync(
            dependencyName: "Some.DotNet.Tool",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                (".config/dotnet-tools.json", """
                    {
                      "version": 1,
                      "isRoot": true,
                      "tools": {
                        "some.dotnet.tool": {
                          "version": "1.0.0",
                          "commands": [
                            "some.dotnet.tool"
                          ]
                        },
                        "some-other-tool": {
                          "version": "2.1.3",
                          "commands": [
                            "some-other-tool"
                          ]
                        }
                      }
                    }
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [
                (".config/dotnet-tools.json", """
                    {
                      "version": 1,
                      "isRoot": true,
                      "tools": {
                        "some.dotnet.tool": {
                          "version": "1.1.0",
                          "commands": [
                            "some.dotnet.tool"
                          ]
                        },
                        "some-other-tool": {
                          "version": "2.1.3",
                          "commands": [
                            "some-other-tool"
                          ]
                        }
                      }
                    }
                    """)],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.DotNet.Tool", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("1.1.0"), UpdatedFiles = ["/.config/dotnet-tools.json"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_GlobalJson()
    {
        // project is unchanged but `global.json` is updated
        await TestAsync(
            dependencyName: "Some.MSBuild.Sdk",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                ("global.json", """
                    {
                      "sdk": {
                        "version": "6.0.405",
                        "rollForward": "latestPatch"
                      },
                      "msbuild-sdks": {
                        "Some.MSBuild.Sdk": "1.0.0"
                      }
                    }
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "1.0.0"),
                MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "1.1.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [
                ("global.json", """
                    {
                      "sdk": {
                        "version": "6.0.405",
                        "rollForward": "latestPatch"
                      },
                      "msbuild-sdks": {
                        "Some.MSBuild.Sdk": "1.1.0"
                      }
                    }
                    """)],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.MSBuild.Sdk", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("1.1.0"), UpdatedFiles = ["/global.json"] }
            ]
        );
    }

    private static async Task TestAsync(
        string dependencyName,
        string oldDependencyVersion,
        string newDependencyVersion,
        string projectContents,
        (string name, string contents)[] additionalFiles,
        IDiscoveryWorker? discoveryWorker,
        IDependencySolver? dependencySolver,
        IFileWriter? fileWriter,
        string expectedProjectContents,
        (string name, string contents)[] expectedAdditionalFiles,
        UpdateOperationBase[] expectedOperations,
        string projectName = "project.csproj",
        MockNuGetPackage[]? packages = null,
        ExperimentsManager? experimentsManager = null,
        Action<DirectoryInfo>? additionalChecks = null
    )
    {
        // arrange
        var allFiles = new List<(string Path, string Contents)>() { (projectName, projectContents) };
        allFiles.AddRange(additionalFiles);
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync([.. allFiles]);
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDir.DirectoryPath);

        var jobId = "TEST-JOB-ID";
        var logger = new TestLogger();
        experimentsManager ??= new ExperimentsManager() { UseDirectDiscovery = true };
        discoveryWorker ??= new DiscoveryWorker(jobId, experimentsManager, logger);
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var projectPath = new FileInfo(Path.Combine(tempDir.DirectoryPath, projectName));
        dependencySolver ??= new MSBuildDependencySolver(repoContentsPath, projectPath, experimentsManager, logger);
        fileWriter ??= new XmlFileWriter(logger);

        var fileWriterWorker = new FileWriterWorker(discoveryWorker, dependencySolver, fileWriter, logger);

        // act
        var actualUpdateOperations = await fileWriterWorker.RunAsync(
            repoContentsPath,
            projectPath,
            dependencyName,
            NuGetVersion.Parse(oldDependencyVersion),
            NuGetVersion.Parse(newDependencyVersion)
        );

        // assert
        var actualUpdateOperationsJson = actualUpdateOperations.Select(o => JsonSerializer.Serialize(o, RunWorker.SerializerOptions)).ToArray();
        var expectedUpdateOperationsJson = expectedOperations.Select(o => JsonSerializer.Serialize(o, RunWorker.SerializerOptions)).ToArray();
        AssertEx.Equal(expectedUpdateOperationsJson, actualUpdateOperationsJson);

        var expectedFiles = new List<(string Path, string Contents)>() { (projectName, expectedProjectContents) };
        expectedFiles.AddRange(expectedAdditionalFiles);
        foreach (var (path, expectedContents) in expectedFiles)
        {
            var fullPath = Path.Join(tempDir.DirectoryPath, path);
            var actualContents = await File.ReadAllTextAsync(fullPath);
            Assert.Equal(expectedContents.Replace("\r", ""), actualContents.Replace("\r", ""));
        }

        additionalChecks?.Invoke(repoContentsPath);
    }
}
