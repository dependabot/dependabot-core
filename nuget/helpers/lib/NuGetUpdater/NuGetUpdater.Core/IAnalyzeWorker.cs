using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core;

public interface IAnalyzeWorker
{
    Task<AnalysisResult> RunAsync(string repoRoot, WorkspaceDiscoveryResult discovery, DependencyInfo dependencyInfo);
}
