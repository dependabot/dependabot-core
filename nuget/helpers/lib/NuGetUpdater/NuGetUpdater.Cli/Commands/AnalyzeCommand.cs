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
    internal static readonly Option<bool> VerboseOption = new("--verbose", getDefaultValue: () => false);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("analyze", "Determines how to update a dependency based on the workspace discovery information.")
        {
            RepoRootOption,
            DependencyFilePathOption,
            DiscoveryFilePathOption,
            AnalysisFolderOption,
            VerboseOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, discoveryPath, dependencyPath, analysisDirectory, verbose) =>
        {
            var worker = new AnalyzeWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, discoveryPath.FullName, dependencyPath.FullName, analysisDirectory.FullName);
        }, RepoRootOption, DiscoveryFilePathOption, DependencyFilePathOption, AnalysisFolderOption, VerboseOption);

        return command;
    }
}
