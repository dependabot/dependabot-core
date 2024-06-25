using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Cli.Commands;

internal static class DiscoverCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
    internal static readonly Option<string> WorkspaceOption = new("--workspace") { IsRequired = true };
    internal static readonly Option<string> OutputOption = new("--output", () => DiscoveryWorker.DiscoveryResultFileName) { IsRequired = false };
    internal static readonly Option<bool> VerboseOption = new("--verbose", getDefaultValue: () => false);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("discover", "Generates a report of the workspace dependencies and where they are located.")
        {
            RepoRootOption,
            WorkspaceOption,
            OutputOption,
            VerboseOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, workspace, outputPath, verbose) =>
        {
            var worker = new DiscoveryWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, workspace, outputPath);
        }, RepoRootOption, WorkspaceOption, OutputOption, VerboseOption);

        return command;
    }
}
