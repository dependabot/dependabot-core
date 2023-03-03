using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Test;

internal class TestDiscoveryWorker : IDiscoveryWorker
{
    private readonly Func<(string, string), Task<WorkspaceDiscoveryResult>> _getResult;

    public TestDiscoveryWorker(Func<(string, string), Task<WorkspaceDiscoveryResult>> getResult)
    {
        _getResult = getResult;
    }

    public Task<WorkspaceDiscoveryResult> RunAsync(string repoRootPath, string workspacePath)
    {
        return _getResult((repoRootPath, workspacePath));
    }

    public static TestDiscoveryWorker FromResults(params (string RepoRootPath, string WorkspacePath, WorkspaceDiscoveryResult Result)[] results)
    {
        return new TestDiscoveryWorker(((string RepoRootPath, string WorkspacePath) input) =>
        {
            foreach (var set in results)
            {
                if (set.RepoRootPath == input.RepoRootPath &&
                    set.WorkspacePath == input.WorkspacePath)
                {
                    return Task.FromResult(set.Result);
                }
            }

            throw new NotImplementedException($"No saved response for {input}");
        });
    }
}
