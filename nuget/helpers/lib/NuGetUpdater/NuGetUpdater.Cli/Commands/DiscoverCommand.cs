using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Cli.Commands;

internal static class DiscoverCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
    internal static readonly Option<FileInfo> SolutionOrProjectFileOption = new("--solution-or-project") { IsRequired = true };
    internal static readonly Option<bool> VerboseOption = new("--verbose", getDefaultValue: () => false);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("discover", "Generates a report of the workspace depenedencies and where they are located.")
        {
            RepoRootOption,
            SolutionOrProjectFileOption,
            VerboseOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, solutionOrProjectFile, verbose) =>
        {
            var worker = new DiscoveryWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName);
        }, RepoRootOption, SolutionOrProjectFileOption, VerboseOption);

        return command;
    }
}
