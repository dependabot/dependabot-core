using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Test;

internal class TestUpdaterWorker : IUpdaterWorker
{
    private readonly Func<(string, string, string, string, string, bool), Task<UpdateOperationResult>> _getResult;

    public TestUpdaterWorker(Func<(string, string, string, string, string, bool), Task<UpdateOperationResult>> getResult)
    {
        _getResult = getResult;
    }

    public Task<UpdateOperationResult> RunAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        return _getResult((repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive));
    }

    public static TestUpdaterWorker FromResults(params (string RepoRootPath, string WorkspacePath, string DependencyName, string PreviousDependencyVersion, string NewDependencyVersion, bool IsTransitive, UpdateOperationResult Result)[] results)
    {
        return new TestUpdaterWorker(((string RepoRootPath, string WorkspacePath, string DependencyName, string PreviousDependencyVersion, string NewDependencyVersion, bool IsTransitive) input) =>
        {
            foreach (var set in results)
            {
                if (set.RepoRootPath == input.RepoRootPath &&
                    set.WorkspacePath == input.WorkspacePath &&
                    set.DependencyName == input.DependencyName &&
                    set.PreviousDependencyVersion == input.PreviousDependencyVersion &&
                    set.NewDependencyVersion == input.NewDependencyVersion &&
                    set.IsTransitive == input.IsTransitive)
                {
                    return Task.FromResult(set.Result);
                }
            }

            throw new NotImplementedException($"No saved response for {input}");
        });
    }
}
