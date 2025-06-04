using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Core.Test;

internal class TestApiHandler : IApiHandler
{
    private readonly List<(Type, object)> _receivedMessages = new();

    public IEnumerable<(Type Type, object Object)> ReceivedMessages => _receivedMessages;

    public Task SendAsync(string endpoint, object body, string method)
    {
        _receivedMessages.Add((body.GetType(), body));
        return Task.CompletedTask;
    }
}
