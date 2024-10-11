using System.Diagnostics;

namespace NuGetUpdater.Core.Test;

public class TestLogger : ILogger
{
    public void Log(string message)
    {
        Debug.WriteLine(message);
    }
}
