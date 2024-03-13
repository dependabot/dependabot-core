using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Cli.Commands;

internal static class DiscoverCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
    internal static readonly Option<FileSystemInfo> WorkspaceOption = new("--workspace") { IsRequired = true };
    internal static readonly Option<bool> VerboseOption = new("--verbose", getDefaultValue: () => false);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("discover", "Generates a report of the workspace depenedencies and where they are located.")
        {
            RepoRootOption,
            WorkspaceOption,
            VerboseOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, workspace, verbose) =>
        {
            var worker = new DiscoveryWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, workspace.FullName);
        }, RepoRootOption, WorkspaceOption, VerboseOption);

        return command;
    }
}
