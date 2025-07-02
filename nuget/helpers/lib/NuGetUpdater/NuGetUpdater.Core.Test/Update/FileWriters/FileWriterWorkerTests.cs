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
    public async Task EndToEnd()
    {
        await TestAsync(
            dependencyName: "Some.Dependency",
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

    private static async Task TestAsync(
        string dependencyName,
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
        ExperimentsManager? experimentsManager = null
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
        fileWriter ??= new XmlFileWriter();

        var fileWriterWorker = new FileWriterWorker(discoveryWorker, dependencySolver, fileWriter, logger);

        // act
        var actualUpdateOperations = await fileWriterWorker.RunAsync(
            repoContentsPath,
            projectPath,
            dependencyName,
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
    }
}
