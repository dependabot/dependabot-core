using System;
using System.Diagnostics;
using System.Text;
using System.Threading.Tasks;

namespace NuGetUpdater.Core;

public static class ProcessEx
{
    public static Task<(int ExitCode, string Output, string Error)> RunAsync(string fileName, string arguments = "", string? workingDirectory = null)
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

        if (workingDirectory is not null)
        {
            process.StartInfo.WorkingDirectory = workingDirectory;
        }

        var stdout = new StringBuilder();
        var stderr = new StringBuilder();

        process.OutputDataReceived += (_, e) => stdout.AppendLine(e.Data);
        process.ErrorDataReceived += (_, e) => stderr.AppendLine(e.Data);

        process.Exited += (sender, args) =>
        {
            tcs.TrySetResult((process.ExitCode, stdout.ToString(), stderr.ToString()));
            process.Dispose();
        };

#if DEBUG
        // don't hang when running locally
        var timeout = TimeSpan.FromSeconds(20);
        Task.Delay(timeout).ContinueWith(_ =>
        {
            if (!tcs.Task.IsCompleted && !Debugger.IsAttached)
            {
                tcs.SetException(new Exception($"Process failed to exit after {timeout.TotalSeconds} seconds: {fileName} {arguments}\nstdout:\n{stdout}\n\nstderr:\n{stderr}"));
            }
        });
#endif

        if (!process.Start())
        {
            throw new InvalidOperationException("Process failed to start");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        return tcs.Task;
    }
}
