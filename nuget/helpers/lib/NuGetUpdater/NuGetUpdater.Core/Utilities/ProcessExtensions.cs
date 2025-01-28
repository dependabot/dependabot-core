using System.Diagnostics;
using System.Text;

namespace NuGetUpdater.Core;

public static class ProcessEx
{
    /// <summary>
    /// Run the `dotnet` command with the given values.  This will exclude all `MSBuild*` environment variables from the execution.
    /// </summary>
    public static Task<(int ExitCode, string Output, string Error)> RunDotnetWithoutMSBuildEnvironmentVariablesAsync(IEnumerable<string> arguments, string workingDirectory, ExperimentsManager experimentsManager)
    {
        var environmentVariablesToUnset = new List<string>();
        if (experimentsManager.InstallDotnetSdks)
        {
            // If using the SDK specified by a `global.json` file, these environment variables need to be unset to
            // allow the new process to discover the correct MSBuild binaries to load, and not load the ones that
            // this process is using.
            environmentVariablesToUnset.Add("MSBuildExtensionsPath");
            environmentVariablesToUnset.Add("MSBuildLoadMicrosoftTargetsReadOnly");
            environmentVariablesToUnset.Add("MSBUILDLOGIMPORTS");
            environmentVariablesToUnset.Add("MSBuildSDKsPath");
            environmentVariablesToUnset.Add("MSBUILDTARGETOUTPUTLOGGING");
            environmentVariablesToUnset.Add("MSBUILD_EXE_PATH");
        }

        var environmentVariableOverrides = environmentVariablesToUnset.Select(name => (name, (string?)null));
        return RunAsync("dotnet",
            arguments,
            workingDirectory,
            environmentVariableOverrides
        );
    }

    public static Task<(int ExitCode, string Output, string Error)> RunAsync(
        string fileName,
        IEnumerable<string>? arguments = null,
        string? workingDirectory = null,
        IEnumerable<(string Name, string? Value)>? environmentVariableOverrides = null
    )
    {
        var tcs = new TaskCompletionSource<(int, string, string)>();

        var redirectInitiated = new ManualResetEventSlim();
        var psi = new ProcessStartInfo(fileName, arguments ?? [])
        {
            UseShellExecute = false, // required to redirect output and set environment variables
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var (name, value) in environmentVariableOverrides ?? [])
        {
            psi.EnvironmentVariables[name] = value;
        }

        var process = new Process
        {
            StartInfo = psi,
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
