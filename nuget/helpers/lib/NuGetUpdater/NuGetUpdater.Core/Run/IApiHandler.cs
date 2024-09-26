using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public interface IApiHandler
{
    Task UpdateDependencyList(UpdatedDependencyList updatedDependencyList);
    Task IncrementMetric(IncrementMetric incrementMetric);
    Task CreatePullRequest(CreatePullRequest createPullRequest);
    Task MarkAsProcessed(MarkAsProcessed markAsProcessed);
}
