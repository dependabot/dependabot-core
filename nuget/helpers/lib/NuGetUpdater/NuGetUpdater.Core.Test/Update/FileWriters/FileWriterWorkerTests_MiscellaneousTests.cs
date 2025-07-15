using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class FileWriterWorkerTests_MiscellaneousTests
{
    [Fact]
    public void GetProjectDiscoveryEvaluationOrder()
    {
        // generate an ordered list of project discovery objects from the bottom of the graph to the top

        // arrange
        var repoContentsPath = new DirectoryInfo("/repo/root");
        var startingProjectPath = "client/client.csproj";
        var fullProjectPath = new FileInfo(Path.Join(repoContentsPath.FullName, startingProjectPath));
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "client",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "client.csproj",
                    ReferencedProjectPaths = ["../common/common.csproj", "../utils/utils.csproj"],
                    Dependencies = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
                new ProjectDiscoveryResult()
                {
                    FilePath = "../common/common.csproj",
                    ReferencedProjectPaths = ["../utils/utils.csproj"],
                    Dependencies = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
                new ProjectDiscoveryResult()
                {
                    FilePath = "../utils/utils.csproj",
                    ReferencedProjectPaths = [],
                    Dependencies = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
                // the server project is a red herring; it's not directly referenced by the client project and should not be in the final list
                new ProjectDiscoveryResult()
                {
                    FilePath = "../server/server.csproj",
                    ReferencedProjectPaths = ["../common/common.csproj", "../utils/utils.csproj"],
                    Dependencies = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
            ]
        };

        // act
        var projectDiscoveryOrder = FileWriterWorker.GetProjectDiscoveryEvaluationOrder(repoContentsPath, discoveryResult, fullProjectPath, new TestLogger());

        // assert
        var actualProjectPaths = projectDiscoveryOrder
            .Select(p => Path.Join(repoContentsPath.FullName, discoveryResult.Path, p.FilePath).FullyNormalizedRootedPath())
            .Select(p => Path.GetRelativePath(repoContentsPath.FullName, p).NormalizePathToUnix())
            .ToArray();
        string[] expectedProjectPaths = [
            "utils/utils.csproj",
            "common/common.csproj",
            "client/client.csproj",
        ];
        AssertEx.Equal(expectedProjectPaths, actualProjectPaths);
    }

    [Fact]
    public async Task AllProjectDiscoveryFilesCanBeReadAndRestored()
    {
        // arrange
        var projectDiscoveryResults = new[]
        {
            new ProjectDiscoveryResult()
            {
                FilePath = "client.csproj",
                ReferencedProjectPaths = ["../common/common.csproj", "../utils/utils.csproj"],
                Dependencies = [],
                ImportedFiles = [],
                AdditionalFiles = ["packages.config"],
            },
        };
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("client/client.csproj", "initial client content"),
            ("client/packages.config", "initial packages config content")
        );
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var startingProjectPath = "client/client.csproj";
        var initialStartingDirectory = new DirectoryInfo(Path.GetDirectoryName(Path.Join(repoContentsPath.FullName, startingProjectPath))!);

        // act - overwrite the files with new content then revert
        var originalFileContents = await FileWriterWorker.GetOriginalFileContentsAsync(repoContentsPath, initialStartingDirectory, projectDiscoveryResults);
        await File.WriteAllTextAsync(Path.Join(repoContentsPath.FullName, "client/client.csproj"), "new client content", TestContext.Current.CancellationToken);
        await File.WriteAllTextAsync(Path.Join(repoContentsPath.FullName, "client/packages.config"), "new packages config content", TestContext.Current.CancellationToken);
        await FileWriterWorker.RestoreOriginalFileContentsAsync(originalFileContents);

        // assert
        Assert.Equal("initial client content", await File.ReadAllTextAsync(Path.Join(repoContentsPath.FullName, "client/client.csproj"), TestContext.Current.CancellationToken));
        Assert.Equal("initial packages config content", await File.ReadAllTextAsync(Path.Join(repoContentsPath.FullName, "client/packages.config"), TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task TryPerformFileWrites_ReportsAppropriateUpdatedFilePaths_WhenStartingFromDifferentProjectDirectory()
    {
        // discovery was initiated from the "tests" directory, but we're now evaluating the "client" project for file writes
        // arrange
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("tests/tests.csproj", """
                <Project>
                  <ItemGroup>
                    <PackageReference Include="Some.Package" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """),
            ("client/client.csproj", """
                <Project>
                  <ItemGroup>
                    <PackageReference Include="Some.Package" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """)
        );
        var logger = new TestLogger();
        var fileWriter = new XmlFileWriter(logger);
        var originalDiscoveryDirectory = new DirectoryInfo(Path.Join(tempDir.DirectoryPath, "tests"));
        var projectDiscovery = new ProjectDiscoveryResult()
        {
            FilePath = "../client/client.csproj",
            Dependencies = [new("Some.Package", "1.0.0", DependencyType.PackageReference)],
            ImportedFiles = [],
            AdditionalFiles = [],
        };

        // act
        var updatedFilePaths = await FileWriterWorker.TryPerformFileWritesAsync(
            fileWriter,
            new DirectoryInfo(tempDir.DirectoryPath),
            originalDiscoveryDirectory,
            projectDiscovery,
            [new("Some.Package", "1.0.1", DependencyType.PackageReference)]
        );

        // assert
        AssertEx.Equal(["/client/client.csproj"], updatedFilePaths);
    }
}
