using System.Diagnostics;

namespace NuGetUpdater.Core.Test;

public class TestLogger : ILogger
{
    public void LogRaw(string message)
    {
        Debug.WriteLine(message);
    }
}
