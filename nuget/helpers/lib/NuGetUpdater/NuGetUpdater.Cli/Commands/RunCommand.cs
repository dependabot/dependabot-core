using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Cli.Commands;

internal static class RunCommand
{
    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("run", "Runs a full dependabot job.")
        {
            SharedOptions.JobPathOption,
            SharedOptions.RepoContentsPathOption,
            SharedOptions.CaseInsensitiveRepoContentsPathOption,
            SharedOptions.ApiUrlOption,
            SharedOptions.JobIdOption,
            SharedOptions.BaseCommitShaOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var jobPath = parseResult.GetValue(SharedOptions.JobPathOption);
            var repoContentsPath = parseResult.GetValue(SharedOptions.RepoContentsPathOption);
            var caseInsensitiveRepoContentsPath = parseResult.GetValue(SharedOptions.CaseInsensitiveRepoContentsPathOption);
            var apiUrl = parseResult.GetValue(SharedOptions.ApiUrlOption);
            var jobId = parseResult.GetValue(SharedOptions.JobIdOption);
            var baseCommitSha = parseResult.GetValue(SharedOptions.BaseCommitShaOption);

            var apiHandler = new HttpApiHandler(apiUrl!.ToString(), jobId!);
            var (experimentsManager, _errorResult) = await ExperimentsManager.FromJobFileAsync(jobId!, jobPath!.FullName);
            var logger = new OpenTelemetryLogger();
            var discoverWorker = new DiscoveryWorker(jobId!, experimentsManager, logger);
            var analyzeWorker = new AnalyzeWorker(jobId!, experimentsManager, logger);
            var updateWorker = new UpdaterWorker(jobId!, experimentsManager, logger);
            var worker = new RunWorker(jobId!, apiHandler, discoverWorker, analyzeWorker, updateWorker, logger);
            var result = await worker.RunAsync(jobPath!, repoContentsPath!, caseInsensitiveRepoContentsPath, baseCommitSha!);
            setExitCode(result);
            return 0;
        });

        return command;
    }
}
