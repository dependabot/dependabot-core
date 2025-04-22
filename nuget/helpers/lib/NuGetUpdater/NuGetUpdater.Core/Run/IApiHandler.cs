using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Run;

public interface IApiHandler
{
    Task RecordUpdateJobError(JobErrorBase error);
    Task UpdateDependencyList(UpdatedDependencyList updatedDependencyList);
    Task IncrementMetric(IncrementMetric incrementMetric);
    Task CreatePullRequest(CreatePullRequest createPullRequest);
    Task ClosePullRequest(ClosePullRequest closePullRequest);
    Task UpdatePullRequest(UpdatePullRequest updatePullRequest);
    Task MarkAsProcessed(MarkAsProcessed markAsProcessed);
}
