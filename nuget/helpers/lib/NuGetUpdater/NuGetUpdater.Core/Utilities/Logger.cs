using System;
using System.IO;

namespace NuGetUpdater.Core;

public sealed class Logger
{
    public bool Verbose { get; set; }
    private readonly TextWriter _logOutput;

    public Logger(bool verbose)
    {
        Verbose = verbose;
        _logOutput = Console.Out;
    }

    public void Log(string message)
    {
        if (Verbose)
        {
            _logOutput.WriteLine(message);
        }
    }
}
