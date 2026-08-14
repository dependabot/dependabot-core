using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Clone;
using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Cli.Commands;

internal static class CloneCommand
{
    internal static Command GetCommand(Action<int> setExitCode)
    {
        var command = new Command("clone", "Clones a repository in preparation for a dependabot job.")
        {
            SharedOptions.JobPathOption,
            SharedOptions.RepoContentsPathOption,
            SharedOptions.ApiUrlOption,
            SharedOptions.JobIdOption,
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var jobPath = parseResult.GetValue(SharedOptions.JobPathOption);
            var repoContentsPath = parseResult.GetValue(SharedOptions.RepoContentsPathOption);
            var apiUrl = parseResult.GetValue(SharedOptions.ApiUrlOption);
            var jobId = parseResult.GetValue(SharedOptions.JobIdOption);

            var apiHandler = new HttpApiHandler(apiUrl!.ToString(), jobId!);
            var logger = new OpenTelemetryLogger();
            var gitCommandHandler = new ShellGitCommandHandler(logger);
            var worker = new CloneWorker(jobId!, apiHandler, gitCommandHandler, logger);
            var exitCode = await worker.RunAsync(jobPath!, repoContentsPath!);
            setExitCode(exitCode);
            return exitCode;
        });

        return command;
    }
}
