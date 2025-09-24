using System.Collections.Immutable;
using System.Text.Json;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Update;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

using TestFile = (string Path, string Content);

public class AnalyzeWorkerTestBase : TestBase
{
    protected static async Task TestAnalyzeAsync(
        WorkspaceDiscoveryResult discovery,
        DependencyInfo dependencyInfo,
        ExpectedAnalysisResult expectedResult,
        MockNuGetPackage[]? packages = null,
        TestFile[]? extraFiles = null,
        ExperimentsManager? experimentsManager = null
    )
    {
        var relativeDependencyPath = $"./dependabot/dependency/{dependencyInfo.Name}.json";

        TestFile[] files = [
            (DiscoveryWorker.DiscoveryResultFileName, JsonSerializer.Serialize(discovery, AnalyzeWorker.SerializerOptions)),
            (relativeDependencyPath, JsonSerializer.Serialize(dependencyInfo, AnalyzeWorker.SerializerOptions)),
        ];

        experimentsManager ??= new ExperimentsManager();
        var allFiles = files.Concat(extraFiles ?? []).ToArray();
        var actualResult = await RunAnalyzerAsync(dependencyInfo.Name, allFiles, async directoryPath =>
        {
            await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, directoryPath);

            var discoveryPath = Path.GetFullPath(DiscoveryWorker.DiscoveryResultFileName, directoryPath);
            var dependencyPath = Path.GetFullPath(relativeDependencyPath, directoryPath);

            var worker = new AnalyzeWorker("TEST-JOB-ID", experimentsManager, new TestLogger());
            var result = await worker.RunWithErrorHandlingAsync(directoryPath, discoveryPath, dependencyPath);
            return result;
        });

        ValidateAnalysisResult(expectedResult, actualResult);
    }

    protected static void ValidateAnalysisResult(ExpectedAnalysisResult expectedResult, AnalysisResult actualResult)
    {
        Assert.NotNull(actualResult);
        Assert.Equal(expectedResult.UpdatedVersion, actualResult.UpdatedVersion);
        Assert.Equal(expectedResult.CanUpdate, actualResult.CanUpdate);
        Assert.Equal(expectedResult.VersionComesFromMultiDependencyProperty, actualResult.VersionComesFromMultiDependencyProperty);
        ValidateDependencies(expectedResult.UpdatedDependencies, actualResult.UpdatedDependencies);
        Assert.Equal(expectedResult.ExpectedUpdatedDependenciesCount ?? expectedResult.UpdatedDependencies.Length, actualResult.UpdatedDependencies.Length);
        ValidateResult(expectedResult, actualResult);

        return;

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
                Assert.Equal(expectedDependency.InfoUrl, actualDependency.InfoUrl);
            }
        }
    }

    protected static void ValidateResult(ExpectedAnalysisResult? expectedResult, AnalysisResult actualResult)
    {
        if (expectedResult?.Error is not null)
        {
            ValidateError(expectedResult.Error, actualResult.Error);
        }
        else
        {
            Assert.Null(actualResult.Error);
        }
    }

    protected static async Task<AnalysisResult> RunAnalyzerAsync(string dependencyName, TestFile[] files, Func<string, Task<AnalysisResult>> action)
    {
        // write initial files
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);

        // run discovery
        var result = await action(temporaryDirectory.DirectoryPath);
        return result;
    }
}
