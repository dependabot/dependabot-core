using System;
using System.CommandLine;
using System.IO;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli.Commands;

internal static class UpdateCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
    internal static readonly Option<FileInfo> SolutionOrProjectFileOption = new("--solution-or-project") { IsRequired = true };
    internal static readonly Option<string> DependencyNameOption = new("--dependency") { IsRequired = true };
    internal static readonly Option<string> NewVersionOption = new("--new-version") { IsRequired = true };
    internal static readonly Option<string> PreviousVersionOption = new("--previous-version") { IsRequired = true };
    internal static readonly Option<bool> IsTransitiveOption = new("--transitive", getDefaultValue: () => false);
    internal static readonly Option<bool> VerboseOption = new("--verbose", getDefaultValue: () => false);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("update", "Applies the changes from an analysis report to update a dependency.")
        {
            RepoRootOption,
            SolutionOrProjectFileOption,
            DependencyNameOption,
            NewVersionOption,
            PreviousVersionOption,
            IsTransitiveOption,
            VerboseOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, solutionOrProjectFile, dependencyName, newVersion, previousVersion, isTransitive, verbose) =>
        {
            var worker = new UpdaterWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName, dependencyName, previousVersion, newVersion, isTransitive);
            setExitCode(0);
        }, RepoRootOption, SolutionOrProjectFileOption, DependencyNameOption, NewVersionOption, PreviousVersionOption, IsTransitiveOption, VerboseOption);

        return command;
    }
}
