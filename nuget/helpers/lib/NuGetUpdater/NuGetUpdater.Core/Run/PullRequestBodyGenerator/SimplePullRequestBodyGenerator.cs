using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal class SimplePullRequestBodyGenerator : IPullRequestBodyGenerator
{
    public Task<string> GeneratePullRequestBodyTextAsync(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, ImmutableArray<ReportedDependency> updatedDependencies)
    {
        var prBody = UpdateOperationBase.GenerateUpdateOperationReport(updateOperationsPerformed, includeFileNames: false);
        return Task.FromResult(prBody);
    }
}
