using System.Collections.Immutable;
using System.Diagnostics.CodeAnalysis;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Update;
using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

using TestFile = (string Path, string Content);

public class DiscoveryWorkerTestBase : TestBase
{
    protected static async Task TestDiscoveryAsync(
        string workspacePath,
        TestFile[] files,
        ExpectedWorkspaceDiscoveryResult expectedResult,
        MockNuGetPackage[]? packages = null,
        bool includeCommonPackages = true,
        ExperimentsManager? experimentsManager = null,
        string? repoContentsPath = null)
    {
        experimentsManager ??= new ExperimentsManager();
        var actualResult = await RunDiscoveryAsync(files, async directoryPath =>
        {
            await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, directoryPath, includeCommonPackages: includeCommonPackages);

            repoContentsPath ??= directoryPath;
            var worker = new DiscoveryWorker("TEST-JOB-ID", experimentsManager, new TestLogger());
            var result = await worker.RunWithErrorHandlingAsync(repoContentsPath, workspacePath);
            return result;
        });

        ValidateWorkspaceResult(expectedResult, actualResult, experimentsManager);
    }

    protected static void ValidateWorkspaceResult(ExpectedWorkspaceDiscoveryResult expectedResult, WorkspaceDiscoveryResult actualResult, ExperimentsManager experimentsManager)
    {
        Assert.NotNull(actualResult);
        Assert.Equal(expectedResult.Path.NormalizePathToUnix(), actualResult.Path.NormalizePathToUnix());
        ValidateResultWithDependencies(expectedResult.GlobalJson, actualResult.GlobalJson);
        ValidateResultWithDependencies(expectedResult.DotNetToolsJson, actualResult.DotNetToolsJson);
        ValidateProjectResults(expectedResult.Projects, actualResult.Projects);
        Assert.Equal(expectedResult.ExpectedProjectCount ?? expectedResult.Projects.Length, actualResult.Projects.Length);
        ValidateDiscoveryOperationResult(expectedResult, actualResult);

        return;

        static void ValidateResultWithDependencies(ExpectedDependencyDiscoveryResult? expectedResult, IDiscoveryResultWithDependencies? actualResult)
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
    }

    protected static void ValidateDiscoveryOperationResult(ExpectedWorkspaceDiscoveryResult? expectedResult, WorkspaceDiscoveryResult actualResult)
    {
        if (expectedResult?.Error is not null)
        {
            ValidateError(expectedResult.Error, actualResult.Error);
        }
        else if (expectedResult?.ErrorRegex is not null)
        {
            ValidateErrorRegex(expectedResult.ErrorRegex, actualResult.Error);
        }
        else
        {
            Assert.Null(actualResult.Error);
        }
    }

    internal static void ValidateProjectResults(ImmutableArray<ExpectedSdkProjectDiscoveryResult> expectedProjects, ImmutableArray<ProjectDiscoveryResult> actualProjects)
    {
        if (expectedProjects.IsDefaultOrEmpty)
        {
            return;
        }

        foreach (var expectedProject in expectedProjects)
        {
            var actualProject = actualProjects.SingleOrDefault(p => p.FilePath.NormalizePathToUnix() == expectedProject.FilePath.NormalizePathToUnix());
            Assert.True(actualProject is not null, $"Unable to find project with path `{expectedProject.FilePath.NormalizePathToUnix()}` in collection [{string.Join(", ", actualProjects.Select(p => p.FilePath))}]");
            Assert.Equal(expectedProject.FilePath.NormalizePathToUnix(), actualProject.FilePath.NormalizePathToUnix());

            var actualProperties = actualProject.Properties;
            AssertEx.Equal(expectedProject.Properties, actualProperties, PropertyComparer.Instance);
            AssertEx.Equal(expectedProject.TargetFrameworks, actualProject.TargetFrameworks);
            AssertEx.Equal(expectedProject.ReferencedProjectPaths, actualProject.ReferencedProjectPaths);
            AssertEx.Equal(expectedProject.ImportedFiles, actualProject.ImportedFiles);
            AssertEx.Equal(expectedProject.AdditionalFiles, actualProject.AdditionalFiles);

            // some dependencies are byproducts of the test framework and shouldn't be returned to make the tests more deterministic
            var forbiddenTestDependencies = new HashSet<string>(["Microsoft.NETFramework.ReferenceAssemblies"], StringComparer.OrdinalIgnoreCase);
            var actualDependencies = actualProject.Dependencies.Where(d => !forbiddenTestDependencies.Contains(d.Name)).ToImmutableArray();

            ValidateDependencies(expectedProject.Dependencies, actualDependencies);
            Assert.Equal(expectedProject.ExpectedDependencyCount ?? expectedProject.Dependencies.Length, actualDependencies.Length);
        }
    }

    internal static void ValidateDependencies(ImmutableArray<Dependency> expectedDependencies, ImmutableArray<Dependency> actualDependencies)
    {
        if (expectedDependencies.IsDefault)
        {
            return;
        }

        foreach (var expectedDependency in expectedDependencies)
        {
            var matchingDependencies = actualDependencies.Where(d =>
            {
                return d.Name == expectedDependency.Name
                    && d.Type == expectedDependency.Type
                    && d.Version == expectedDependency.Version
                    && d.IsDirect == expectedDependency.IsDirect
                    && d.IsTransitive == expectedDependency.IsTransitive
                    && d.TargetFrameworks.SequenceEqual(expectedDependency.TargetFrameworks);
            }).ToArray();
            Assert.True(matchingDependencies.Length == 1, $"""
                Unable to find 1 dependency matching; found {matchingDependencies.Length}:
                    Name: {expectedDependency.Name}
                    Type: {expectedDependency.Type}
                    Version: {expectedDependency.Version}
                    IsDirect: {expectedDependency.IsDirect}
                    IsTransitive: {expectedDependency.IsTransitive}
                    TargetFrameworks: {string.Join(", ", expectedDependency.TargetFrameworks ?? [])}
                Found:{"\n\t"}{string.Join("\n\t", actualDependencies)}
                """);
        }
    }

    protected static async Task<WorkspaceDiscoveryResult> RunDiscoveryAsync(TestFile[] files, Func<string, Task<WorkspaceDiscoveryResult>> action)
    {
        // write initial files
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);

        // run discovery
        var result = await action(temporaryDirectory.DirectoryPath);
        return result;
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
