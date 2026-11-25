using System.Threading.Channels;

namespace NuGetUpdater.Core.Test.Utilities;

internal sealed class GatedRequests<T>(IEnumerable<string> keys)
{
    private readonly Dictionary<string, TaskCompletionSource<T>> _responses = keys.ToDictionary(
        key => key,
        _ => new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously));
    private readonly Channel<string> _requests = Channel.CreateUnbounded<string>();
    private readonly object _gate = new();
    private int _activeRequests;

    public int PeakConcurrency { get; private set; }
    public int RequestCount { get; private set; }
    public int ActiveRequests => Volatile.Read(ref _activeRequests);

    public async Task<T> GetResponseAsync(string key, CancellationToken cancellationToken = default)
    {
        var active = Interlocked.Increment(ref _activeRequests);
        lock (_gate)
        {
            PeakConcurrency = Math.Max(PeakConcurrency, active);
            RequestCount++;
        }

        try
        {
            var response = _responses[key];
            _requests.Writer.TryWrite(key);
            return await response.Task.WaitAsync(cancellationToken);
        }
        finally
        {
            Interlocked.Decrement(ref _activeRequests);
        }
    }

    public async Task<string[]> ReadRequestsAsync(int count, CancellationToken cancellationToken)
    {
        var requests = new string[count];
        for (var i = 0; i < count; i++)
        {
            requests[i] = await _requests.Reader.ReadAsync(cancellationToken).AsTask()
                .WaitAsync(TimeSpan.FromSeconds(30), cancellationToken);
        }

        return requests;
    }

    public void Respond(string key, T response) => _responses[key].TrySetResult(response);

    public void Fail(string key, Exception exception) => _responses[key].TrySetException(exception);

    public void RespondAll(Func<string, T> response)
    {
        foreach (var key in _responses.Keys)
        {
            Respond(key, response(key));
        }
    }
}
