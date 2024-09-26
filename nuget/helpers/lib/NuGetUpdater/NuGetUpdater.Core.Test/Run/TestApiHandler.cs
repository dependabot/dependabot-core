using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Test;

internal class TestApiHandler : IApiHandler
{
    private readonly List<(Type, object)> _receivedMessages = new();

    public IEnumerable<(Type Type, object Object)> ReceivedMessages => _receivedMessages;

    public Task UpdateDependencyList(UpdatedDependencyList updatedDependencyList)
    {
        _receivedMessages.Add((typeof(UpdatedDependencyList), updatedDependencyList));
        return Task.CompletedTask;
    }

    public Task IncrementMetric(IncrementMetric incrementMetric)
    {
        _receivedMessages.Add((typeof(IncrementMetric), incrementMetric));
        return Task.CompletedTask;
    }

    public Task CreatePullRequest(CreatePullRequest createPullRequest)
    {
        _receivedMessages.Add((typeof(CreatePullRequest), createPullRequest));
        return Task.CompletedTask;
    }

    public Task MarkAsProcessed(MarkAsProcessed markAsProcessed)
    {
        _receivedMessages.Add((typeof(MarkAsProcessed), markAsProcessed));
        return Task.CompletedTask;
    }
}
