using System.Collections.Immutable;
using System.Diagnostics.CodeAnalysis;
using System.Text.Json;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

using TestFile = (string Path, string Content);

public class DiscoveryWorkerTestBase
{
    protected static async Task TestDiscoveryAsync(
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
        Assert.Equal(expectedResult.FilePath.NormalizePathToUnix(), actualResult.FilePath.NormalizePathToUnix());
        ValidateDirectoryPackagesProps(expectedResult.DirectoryPackagesProps, actualResult.DirectoryPackagesProps);
        ValidateResultWithDependencies(expectedResult.GlobalJson, actualResult.GlobalJson);
        ValidateResultWithDependencies(expectedResult.DotNetToolsJson, actualResult.DotNetToolsJson);
        ValidateProjectResults(expectedResult.Projects, actualResult.Projects);
        Assert.Equal(expectedResult.ExpectedProjectCount ?? expectedResult.Projects.Length, actualResult.Projects.Length);

        return;

        void ValidateResultWithDependencies(ExpectedDependencyDiscoveryResult? expectedResult, IDiscoveryResultWithDependencies? actualResult)
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

            Assert.Equal(expectedResult.FilePath.NormalizePathToUnix(), actualResult.FilePath.NormalizePathToUnix());
            ValidateDependencies(expectedResult.Dependencies, actualResult.Dependencies);
            Assert.Equal(expectedResult.ExpectedDependencyCount ?? expectedResult.Dependencies.Length, actualResult.Dependencies.Length);
        }

        void ValidateProjectResults(ImmutableArray<ExpectedSdkProjectDiscoveryResult> expectedProjects, ImmutableArray<ProjectDiscoveryResult> actualProjects)
        {
            if (expectedProjects.IsDefaultOrEmpty)
            {
                return;
            }

            foreach (var expectedProject in expectedProjects)
            {
                var actualProject = actualProjects.Single(p => p.FilePath.NormalizePathToUnix() == expectedProject.FilePath.NormalizePathToUnix());

                Assert.Equal(expectedProject.FilePath.NormalizePathToUnix(), actualProject.FilePath.NormalizePathToUnix());
                AssertEx.Equal(expectedProject.Properties, actualProject.Properties, PropertyComparer.Instance);
                AssertEx.Equal(expectedProject.TargetFrameworks, actualProject.TargetFrameworks);
                AssertEx.Equal(expectedProject.ReferencedProjectPaths.Select(PathHelper.NormalizePathToUnix), actualProject.ReferencedProjectPaths.Select(PathHelper.NormalizePathToUnix));
                ValidateDependencies(expectedProject.Dependencies, actualProject.Dependencies);
                Assert.Equal(expectedProject.ExpectedDependencyCount ?? expectedProject.Dependencies.Length, actualProject.Dependencies.Length);
            }
        }

        void ValidateDirectoryPackagesProps(ExpectedDirectoryPackagesPropsDiscovertyResult? expected, DirectoryPackagesPropsDiscoveryResult? actual)
        {
            ValidateResultWithDependencies(expected, actual);
            Assert.Equal(expected?.IsTransitivePinningEnabled, actual?.IsTransitivePinningEnabled);
        }

        void ValidateDependencies(ImmutableArray<Dependency> expectedDependencies, ImmutableArray<Dependency> actualDependencies)
        {
            if (expectedDependencies.IsDefault)
            {
                return;
            }

            foreach (var expectedDependency in expectedDependencies)
            {
                var actualDependency = actualDependencies.Single(d => d.Name == expectedDependency.Name);
                Assert.Equal(expectedDependency.Name, actualDependency.Name);
                Assert.Equal(expectedDependency.Version, actualDependency.Version);
                Assert.Equal(expectedDependency.Type, actualDependency.Type);
                AssertEx.Equal(expectedDependency.TargetFrameworks, actualDependency.TargetFrameworks);
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

    internal class PropertyComparer : IEqualityComparer<Property>
    {
        public static PropertyComparer Instance { get; } = new();

        public bool Equals(Property? x, Property? y)
        {
            return x?.Name == y?.Name &&
                   x?.Value == y?.Value &&
                   x?.SourceFilePath.NormalizePathToUnix() == y?.SourceFilePath.NormalizePathToUnix();
        }

        public int GetHashCode([DisallowNull] Property obj)
        {
            throw new NotImplementedException();
        }
    }
}
