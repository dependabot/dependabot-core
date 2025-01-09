using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Cli.Commands;

internal static class RunCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> RepoContentsPathOption = new("--repo-contents-path") { IsRequired = true };
    internal static readonly Option<Uri> ApiUrlOption = new("--api-url") { IsRequired = true };
    internal static readonly Option<string> JobIdOption = new("--job-id") { IsRequired = true };
    internal static readonly Option<FileInfo> OutputPathOption = new("--output-path") { IsRequired = true };
    internal static readonly Option<string> BaseCommitShaOption = new("--base-commit-sha") { IsRequired = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("run", "Runs a full dependabot job.")
        {
            JobPathOption,
            RepoContentsPathOption,
            ApiUrlOption,
            JobIdOption,
            OutputPathOption,
            BaseCommitShaOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (jobPath, repoContentsPath, apiUrl, jobId, outputPath, baseCommitSha) =>
        {
            var apiHandler = new HttpApiHandler(apiUrl.ToString(), jobId);
            var (experimentsManager, _errorResult) = await ExperimentsManager.FromJobFileAsync(jobPath.FullName);
            var logger = new ConsoleLogger();
            var discoverWorker = new DiscoveryWorker(experimentsManager, logger);
            var analyzeWorker = new AnalyzeWorker(experimentsManager, logger);
            var updateWorker = new UpdaterWorker(experimentsManager, logger);
            var worker = new RunWorker(jobId, apiHandler, discoverWorker, analyzeWorker, updateWorker, logger);
            await worker.RunAsync(jobPath, repoContentsPath, baseCommitSha, outputPath);
        }, JobPathOption, RepoContentsPathOption, ApiUrlOption, JobIdOption, OutputPathOption, BaseCommitShaOption);

        return command;
    }
}
