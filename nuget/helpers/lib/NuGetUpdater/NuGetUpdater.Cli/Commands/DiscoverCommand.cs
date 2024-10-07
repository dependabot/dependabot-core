using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Cli.Commands;

internal static class DiscoverCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { IsRequired = true };
    internal static readonly Option<string> WorkspaceOption = new("--workspace") { IsRequired = true };
    internal static readonly Option<FileInfo> OutputOption = new("--output") { IsRequired = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("discover", "Generates a report of the workspace dependencies and where they are located.")
        {
            RepoRootOption,
            WorkspaceOption,
            OutputOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, workspace, outputPath) =>
        {
            var worker = new DiscoveryWorker(new ConsoleLogger());
            await worker.RunAsync(repoRoot.FullName, workspace, outputPath.FullName);
        }, RepoRootOption, WorkspaceOption, OutputOption);

        return command;
    }
}
