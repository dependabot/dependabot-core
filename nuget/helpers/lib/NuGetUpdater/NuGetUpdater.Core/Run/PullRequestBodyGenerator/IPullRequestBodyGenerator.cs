using System.Collections.Immutable;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

public interface IPullRequestBodyGenerator
{
    public Task<string> GeneratePullRequestBodyTextAsync(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, ImmutableArray<ReportedDependency> updatedDependencies);
}
