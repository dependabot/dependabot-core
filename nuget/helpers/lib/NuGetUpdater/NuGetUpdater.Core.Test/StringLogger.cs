namespace NuGetUpdater.Core.Test;

public class StringLogger : ILogger
{
    private readonly List<string> _messages = [];

    public IReadOnlyList<string> Messages => _messages;

    public void LogRaw(string message)
    {
        _messages.Add(message);
    }
}
