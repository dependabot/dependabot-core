using System.Collections.Immutable;
using System.Text.Json;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.Update;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

using TestFile = (string Path, string Content);

public class AnalyzeWorkerTestBase
{
    protected static async Task TestAnalyzeAsync(
        WorkspaceDiscoveryResult discovery,
        DependencyInfo dependencyInfo,
        ExpectedAnalysisResult expectedResult,
        MockNuGetPackage[]? packages = null,
        TestFile[]? extraFiles = null)
    {
        var relativeDependencyPath = $"./dependabot/dependency/{dependencyInfo.Name}.json";

        TestFile[] files = [
            (DiscoveryWorker.DiscoveryResultFileName, JsonSerializer.Serialize(discovery, AnalyzeWorker.SerializerOptions)),
            (relativeDependencyPath, JsonSerializer.Serialize(dependencyInfo, AnalyzeWorker.SerializerOptions)),
        ];

        var allFiles = files.Concat(extraFiles ?? []).ToArray();
        var actualResult = await RunAnalyzerAsync(dependencyInfo.Name, allFiles, async directoryPath =>
        {
            await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, directoryPath);

            var discoveryPath = Path.GetFullPath(DiscoveryWorker.DiscoveryResultFileName, directoryPath);
            var dependencyPath = Path.GetFullPath(relativeDependencyPath, directoryPath);
            var analysisPath = Path.GetFullPath(AnalyzeWorker.AnalysisDirectoryName, directoryPath);

            var worker = new AnalyzeWorker(new Logger(verbose: true));
            await worker.RunAsync(directoryPath, discoveryPath, dependencyPath, analysisPath);
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
        Assert.Equal(expectedResult.ErrorType, actualResult.ErrorType);
        Assert.Equal(expectedResult.ErrorDetails, actualResult.ErrorDetails);

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

    protected static async Task<AnalysisResult> RunAnalyzerAsync(string dependencyName, TestFile[] files, Func<string, Task> action)
    {
        // write initial files
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);

        // run discovery
        await action(temporaryDirectory.DirectoryPath);

        // gather results
        var resultPath = Path.Join(temporaryDirectory.DirectoryPath, AnalyzeWorker.AnalysisDirectoryName, $"{dependencyName}.json");
        var resultJson = await File.ReadAllTextAsync(resultPath);
        return JsonSerializer.Deserialize<AnalysisResult>(resultJson, DiscoveryWorker.SerializerOptions)!;
    }
}
