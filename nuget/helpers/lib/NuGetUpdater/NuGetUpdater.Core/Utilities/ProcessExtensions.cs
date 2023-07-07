using System.Diagnostics;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

public static class ProcessEx
{
    public static Task<(int ExitCode, string Output, string Error)> RunAsync(string fileName, string arguments = "")
    {
        var tcs = new TaskCompletionSource<(int, string, string)>();

        var process = new Process
        {
            StartInfo =
            {
                FileName = fileName,
                Arguments = arguments,
                UseShellExecute = false, // required to redirect output
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            },
            EnableRaisingEvents = true
        };

        process.Exited += (sender, args) =>
        {
            tcs.SetResult((process.ExitCode, process.StandardOutput.ReadToEnd(), process.StandardError.ReadToEnd()));
            process.Dispose();
        };

        process.Start();

        return tcs.Task;
    }
}