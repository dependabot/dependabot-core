using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Test;

internal class TestApiHandler : IApiHandler
{
    private readonly List<(Type, object)> _receivedMessages = new();

    public IEnumerable<(Type Type, object Object)> ReceivedMessages => _receivedMessages;

    public Task RecordUpdateJobError(JobErrorBase error)
    {
        _receivedMessages.Add((error.GetType(), error));
        return Task.CompletedTask;
    }

    public Task UpdateDependencyList(UpdatedDependencyList updatedDependencyList)
    {
        _receivedMessages.Add((updatedDependencyList.GetType(), updatedDependencyList));
        return Task.CompletedTask;
    }

    public Task IncrementMetric(IncrementMetric incrementMetric)
    {
        _receivedMessages.Add((incrementMetric.GetType(), incrementMetric));
        return Task.CompletedTask;
    }

    public Task CreatePullRequest(CreatePullRequest createPullRequest)
    {
        _receivedMessages.Add((createPullRequest.GetType(), createPullRequest));
        return Task.CompletedTask;
    }

    public Task ClosePullRequest(ClosePullRequest closePullRequest)
    {
        _receivedMessages.Add((closePullRequest.GetType(), closePullRequest));
        return Task.CompletedTask;
    }

    public Task UpdatePullRequest(UpdatePullRequest updatePullRequest)
    {
        _receivedMessages.Add((updatePullRequest.GetType(), updatePullRequest));
        return Task.CompletedTask;
    }

    public Task MarkAsProcessed(MarkAsProcessed markAsProcessed)
    {
        _receivedMessages.Add((markAsProcessed.GetType(), markAsProcessed));
        return Task.CompletedTask;
    }
}
