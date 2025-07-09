using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class FileWriterWorkerTests_ProjectDiscoveryEvaluationOrderTests
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
}
