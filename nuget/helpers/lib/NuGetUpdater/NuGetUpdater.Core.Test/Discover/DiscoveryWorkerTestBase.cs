using System.Collections.Immutable;
using System.Text.Json;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

using TestFile = (string Path, string Content);

public class DiscoveryWorkerTestBase
{
    protected static async Task TestDiscovery(
        string workspacePath,
        TestFile[] files,
        ExpectedWorkspaceDiscoveryResult expectedResult)
    {
        var actualResult = await RunDiscoveryAsync(files, async directoryPath =>
        {
            var worker = new DiscoveryWorker(new Logger(verbose: true));
            await worker.RunAsync(directoryPath, workspacePath, DiscoveryWorker.DiscoveryResultFileName);
        });

        ValidateWorkspaceResult(expectedResult, actualResult);
    }

    protected static void ValidateWorkspaceResult(ExpectedWorkspaceDiscoveryResult expectedResult, WorkspaceDiscoveryResult actualResult)
    {
        Assert.NotNull(actualResult);
        Assert.Equal(expectedResult.FilePath, actualResult.FilePath);
        Assert.Equal(expectedResult.Type, actualResult.Type);
        AssertEx.Equal(expectedResult.TargetFrameworks, actualResult.TargetFrameworks);
        ValidateDirectoryPackagesProps(expectedResult.DirectoryPackagesProps, actualResult.DirectoryPackagesProps);
        ValidateResultWithDependencies(expectedResult.GlobalJson, actualResult.GlobalJson);
        ValidateResultWithDependencies(expectedResult.DotNetToolsJson, actualResult.DotNetToolsJson);
        ValidateProjectResults(expectedResult.Projects, actualResult.Projects);
        Assert.Equal(expectedResult.ExpectedProjectCount ?? expectedResult.Projects.Length, actualResult.Projects.Length);

        return;

        void ValidateResultWithDependencies(IDiscoveryResultWithDependencies? expectedResult, IDiscoveryResultWithDependencies? actualResult)
        {
            if (expectedResult is null)
            {
                Assert.Null(actualResult);
                return;
            }
            else
            {
                Assert.NotNull(actualResult);
            }

            Assert.Equal(expectedResult.FilePath, actualResult.FilePath);
            ValidateDependencies(expectedResult.Dependencies, actualResult.Dependencies);
        }

        void ValidateProjectResults(ImmutableArray<ExpectedSdkProjectDiscoveryResult> expectedProjects, ImmutableArray<ProjectDiscoveryResult> actualProjects)
        {
            foreach (var expectedProject in expectedProjects)
            {
                var actualProject = actualProjects.Single(p => p.FilePath == expectedProject.FilePath);

                Assert.Equal(expectedProject.FilePath, actualProject.FilePath);
                AssertEx.Equal(expectedProject.Properties, actualProject.Properties);
                AssertEx.Equal(expectedProject.TargetFrameworks, actualProject.TargetFrameworks);
                AssertEx.Equal(expectedProject.ReferencedProjectPaths, actualProject.ReferencedProjectPaths);
                ValidateDependencies(expectedProject.Dependencies, actualProject.Dependencies);
                Assert.Equal(expectedProject.ExpectedDependencyCount ?? expectedProject.Dependencies.Length, actualProject.Dependencies.Length);
            }
        }

        void ValidateDirectoryPackagesProps(DirectoryPackagesPropsDiscoveryResult? expected, DirectoryPackagesPropsDiscoveryResult? actual)
        {
            ValidateResultWithDependencies(expected, actual);
            Assert.Equal(expected?.IsTransitivePinningEnabled, actual?.IsTransitivePinningEnabled);
        }

        void ValidateDependencies(ImmutableArray<Dependency> expectedDependencies, ImmutableArray<Dependency> actualDependencies)
        {
            foreach (var expectedDependency in expectedDependencies)
            {
                var actualDependency = actualDependencies.Single(d => d.Name == expectedDependency.Name);
                Assert.Equal(expectedDependency.Name, actualDependency.Name);
                Assert.Equal(expectedDependency.Version, actualDependency.Version);
                Assert.Equal(expectedDependency.Type, actualDependency.Type);
                Assert.Equal(expectedDependency.IsDirect, actualDependency.IsDirect);
                Assert.Equal(expectedDependency.IsTransitive, actualDependency.IsTransitive);
            }
        }
    }

    protected static async Task<WorkspaceDiscoveryResult> RunDiscoveryAsync(TestFile[] files, Func<string, Task> action)
    {
        // write initial files
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);

        // run discovery
        await action(temporaryDirectory.DirectoryPath);

        // gather results
        var resultPath = Path.Join(temporaryDirectory.DirectoryPath, DiscoveryWorker.DiscoveryResultFileName);
        var resultJson = await File.ReadAllTextAsync(resultPath);
        return JsonSerializer.Deserialize<WorkspaceDiscoveryResult>(resultJson, DiscoveryWorker.SerializerOptions)!;
    }
}
