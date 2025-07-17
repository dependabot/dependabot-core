using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Cli.Commands;

internal static class DiscoverCommand
{
    internal static readonly Option<string> JobIdOption = new("--job-id") { Required = true };
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { Required = true };
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { Required = true };
    internal static readonly Option<string> WorkspaceOption = new("--workspace") { Required = true };
    internal static readonly Option<FileInfo> OutputOption = new("--output") { Required = true };

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

        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var jobId = parseResult.GetValue(JobIdOption);
            var jobPath = parseResult.GetValue(JobPathOption);
            var repoRoot = parseResult.GetValue(RepoRootOption);
            var workspace = parseResult.GetValue(WorkspaceOption);
            var outputPath = parseResult.GetValue(OutputOption);

            var logger = new OpenTelemetryLogger();
            MSBuildHelper.RegisterMSBuild(repoRoot!.FullName, repoRoot.FullName, logger);
            var (experimentsManager, error) = await ExperimentsManager.FromJobFileAsync(jobId!, jobPath!.FullName);
            if (error is not null)
            {
                // to make testing easier, this should be a `WorkspaceDiscoveryResult` object
                var discoveryErrorResult = new WorkspaceDiscoveryResult
                {
                    Error = error,
                    Path = workspace!,
                    Projects = [],
                };
                await DiscoveryWorker.WriteResultsAsync(repoRoot.FullName, outputPath!.FullName, discoveryErrorResult);
                return 0;
            }

            var worker = new DiscoveryWorker(jobId!, experimentsManager, logger);
            await worker.RunAsync(repoRoot.FullName, workspace!, outputPath!.FullName);
            return 0;
        });

        return command;
    }
}
