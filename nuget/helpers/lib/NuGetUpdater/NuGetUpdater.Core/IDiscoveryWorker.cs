using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core;

public interface IDiscoveryWorker
{
    Task<WorkspaceDiscoveryResult> RunAsync(string repoRootPath, string workspacePath);
}
