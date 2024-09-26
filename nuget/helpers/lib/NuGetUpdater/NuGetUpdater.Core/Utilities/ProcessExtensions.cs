using System.Diagnostics;
using System.Text;

namespace NuGetUpdater.Core;

public static class ProcessEx
{
    public static Task<(int ExitCode, string Output, string Error)> RunAsync(string fileName, IEnumerable<string>? arguments = null, string? workingDirectory = null)
    {
        var tcs = new TaskCompletionSource<(int, string, string)>();

        var redirectInitiated = new ManualResetEventSlim();
        var process = new Process
        {
            StartInfo = new ProcessStartInfo(fileName, arguments ?? Array.Empty<string>())
            {
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
            // It is necessary to wait until we have invoked 'BeginXReadLine' for our redirected IO. Then,
            // we must call WaitForExit to make sure we've received all OutputDataReceived/ErrorDataReceived calls
            // or else we'll be returning a list we're still modifying. For paranoia, we'll start a task here rather
            // than enter right back into the Process type and start a wait which isn't guaranteed to be safe.
            Task.Run(() =>
            {
                redirectInitiated.Wait();
                redirectInitiated.Dispose();
                redirectInitiated = null;

                process.WaitForExit();

                tcs.TrySetResult((process.ExitCode, stdout.ToString(), stderr.ToString()));
                process.Dispose();
            });
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

        redirectInitiated.Set();

        return tcs.Task;
    }
}
