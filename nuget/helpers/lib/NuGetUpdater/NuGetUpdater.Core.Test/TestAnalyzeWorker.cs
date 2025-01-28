using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Test;

internal class TestAnalyzeWorker : IAnalyzeWorker
{
    private readonly Func<(string, WorkspaceDiscoveryResult, DependencyInfo), Task<AnalysisResult>> _getResult;

    public TestAnalyzeWorker(Func<(string, WorkspaceDiscoveryResult, DependencyInfo), Task<AnalysisResult>> getResult)
    {
        _getResult = getResult;
    }

    public Task<AnalysisResult> RunAsync(string repoRoot, WorkspaceDiscoveryResult discovery, DependencyInfo dependencyInfo)
    {
        return _getResult((repoRoot, discovery, dependencyInfo));
    }

    public static TestAnalyzeWorker FromResults(params (string RepoRoot, WorkspaceDiscoveryResult Discovery, DependencyInfo DependencyInfo, AnalysisResult Result)[] results)
    {
        return new TestAnalyzeWorker(((string RepoRoot, WorkspaceDiscoveryResult Discovery, DependencyInfo DependencyInfo) input) =>
        {
            foreach (var set in results)
            {
                if (set.RepoRoot == input.RepoRoot &&
                    set.Discovery == input.Discovery &&
                    set.DependencyInfo == input.DependencyInfo)
                {
                    return Task.FromResult(set.Result);
                }
            }

            throw new NotImplementedException($"No saved response for {input}");
        });
    }
}
