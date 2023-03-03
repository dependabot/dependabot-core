
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core;

public interface IUpdaterWorker
{
    Task<UpdateOperationResult> RunAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive);
}
