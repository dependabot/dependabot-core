namespace NuGetUpdater.Core;

public sealed class ConsoleLogger : ILogger
{
    public void LogRaw(string message)
    {
        Console.WriteLine(message);
    }
}
