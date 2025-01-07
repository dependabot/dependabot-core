using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Cli.Commands;

internal static class DiscoverCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { IsRequired = true };
    internal static readonly Option<string> WorkspaceOption = new("--workspace") { IsRequired = true };
    internal static readonly Option<FileInfo> OutputOption = new("--output") { IsRequired = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("discover", "Generates a report of the workspace dependencies and where they are located.")
        {
            JobPathOption,
            RepoRootOption,
            WorkspaceOption,
            OutputOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (jobPath, repoRoot, workspace, outputPath) =>
        {
            var (experimentsManager, errorResult) = await ExperimentsManager.FromJobFileAsync(jobPath.FullName);
            if (errorResult is not null)
            {
                // to make testing easier, this should be a `WorkspaceDiscoveryResult` object
                var discoveryErrorResult = new WorkspaceDiscoveryResult
                {
                    Path = workspace,
                    Projects = [],
                    ErrorType = errorResult.ErrorType,
                    ErrorDetails = errorResult.ErrorDetails,
                };
                await DiscoveryWorker.WriteResultsAsync(repoRoot.FullName, outputPath.FullName, discoveryErrorResult);
                return;
            }

            var logger = new ConsoleLogger();
            var worker = new DiscoveryWorker(experimentsManager, logger);
            await worker.RunAsync(repoRoot.FullName, workspace, outputPath.FullName);
        }, JobPathOption, RepoRootOption, WorkspaceOption, OutputOption);

        return command;
    }
}
