using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Cli.Commands;

internal static class AnalyzeCommand
{
    internal static readonly Option<string> JobIdOption = new("--job-id") { Required = true };
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { Required = true };
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { Required = true };
    internal static readonly Option<FileInfo> DependencyFilePathOption = new("--dependency-file-path") { Required = true };
    internal static readonly Option<FileInfo> DiscoveryFilePathOption = new("--discovery-file-path") { Required = true };
    internal static readonly Option<DirectoryInfo> AnalysisFolderOption = new("--analysis-folder-path") { Required = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("analyze", "Determines how to update a dependency based on the workspace discovery information.")
        {
            JobIdOption,
            JobPathOption,
            RepoRootOption,
            DependencyFilePathOption,
            DiscoveryFilePathOption,
            AnalysisFolderOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var jobId = parseResult.GetValue(JobIdOption);
            var jobPath = parseResult.GetValue(JobPathOption);
            var repoRoot = parseResult.GetValue(RepoRootOption);
            var discoveryPath = parseResult.GetValue(DiscoveryFilePathOption);
            var dependencyPath = parseResult.GetValue(DependencyFilePathOption);
            var analysisDirectory = parseResult.GetValue(AnalysisFolderOption);

            var logger = new OpenTelemetryLogger();
            var (experimentsManager, _errorResult) = await ExperimentsManager.FromJobFileAsync(jobId!, jobPath!.FullName);
            var worker = new AnalyzeWorker(jobId!, experimentsManager, logger);
            await worker.RunAsync(repoRoot!.FullName, discoveryPath!.FullName, dependencyPath!.FullName, analysisDirectory!.FullName);
            return 0;
        });

        return command;
    }
}
