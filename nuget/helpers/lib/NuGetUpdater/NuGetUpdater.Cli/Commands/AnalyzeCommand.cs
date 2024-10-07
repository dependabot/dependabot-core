using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Cli.Commands;

internal static class AnalyzeCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { IsRequired = true };
    internal static readonly Option<FileInfo> DependencyFilePathOption = new("--dependency-file-path") { IsRequired = true };
    internal static readonly Option<FileInfo> DiscoveryFilePathOption = new("--discovery-file-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> AnalysisFolderOption = new("--analysis-folder-path") { IsRequired = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("analyze", "Determines how to update a dependency based on the workspace discovery information.")
        {
            RepoRootOption,
            DependencyFilePathOption,
            DiscoveryFilePathOption,
            AnalysisFolderOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, discoveryPath, dependencyPath, analysisDirectory) =>
        {
            var worker = new AnalyzeWorker(new ConsoleLogger());
            await worker.RunAsync(repoRoot.FullName, discoveryPath.FullName, dependencyPath.FullName, analysisDirectory.FullName);
        }, RepoRootOption, DiscoveryFilePathOption, DependencyFilePathOption, AnalysisFolderOption);

        return command;
    }
}
