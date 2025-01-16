using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Cli.Commands;

internal static class DiscoverCommand
{
    internal static readonly Option<string> JobIdOption = new("--job-id") { IsRequired = true };
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { IsRequired = true };
    internal static readonly Option<string> WorkspaceOption = new("--workspace") { IsRequired = true };
    internal static readonly Option<FileInfo> OutputOption = new("--output") { IsRequired = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("discover", "Generates a report of the workspace dependencies and where they are located.")
        {
            JobIdOption,
            JobPathOption,
            RepoRootOption,
            WorkspaceOption,
            OutputOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (jobId, jobPath, repoRoot, workspace, outputPath) =>
        {
            var (experimentsManager, error) = await ExperimentsManager.FromJobFileAsync(jobId, jobPath.FullName);
            if (error is not null)
            {
                // to make testing easier, this should be a `WorkspaceDiscoveryResult` object
                var discoveryErrorResult = new WorkspaceDiscoveryResult
                {
                    Error = error,
                    Path = workspace,
                    Projects = [],
                };
                await DiscoveryWorker.WriteResultsAsync(repoRoot.FullName, outputPath.FullName, discoveryErrorResult);
                return;
            }

            var logger = new ConsoleLogger();
            var worker = new DiscoveryWorker(jobId, experimentsManager, logger);
            await worker.RunAsync(repoRoot.FullName, workspace, outputPath.FullName);
        }, JobIdOption, JobPathOption, RepoRootOption, WorkspaceOption, OutputOption);

        return command;
    }
}
