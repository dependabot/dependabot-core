using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Cli.Commands;

internal static class AnalyzeCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { IsRequired = true };
    internal static readonly Option<FileInfo> DependencyFilePathOption = new("--dependency-file-path") { IsRequired = true };
    internal static readonly Option<FileInfo> DiscoveryFilePathOption = new("--discovery-file-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> AnalysisFolderOption = new("--analysis-folder-path") { IsRequired = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("analyze", "Determines how to update a dependency based on the workspace discovery information.")
        {
            JobPathOption,
            RepoRootOption,
            DependencyFilePathOption,
            DiscoveryFilePathOption,
            AnalysisFolderOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (jobPath, repoRoot, discoveryPath, dependencyPath, analysisDirectory) =>
        {
            var logger = new ConsoleLogger();
            var (experimentsManager, _errorResult) = await ExperimentsManager.FromJobFileAsync(jobPath.FullName);
            var worker = new AnalyzeWorker(experimentsManager, logger);
            await worker.RunAsync(repoRoot.FullName, discoveryPath.FullName, dependencyPath.FullName, analysisDirectory.FullName);
        }, JobPathOption, RepoRootOption, DiscoveryFilePathOption, DependencyFilePathOption, AnalysisFolderOption);

        return command;
    }
}
