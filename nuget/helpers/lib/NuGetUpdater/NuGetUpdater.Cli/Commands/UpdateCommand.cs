using System.CommandLine;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli.Commands;

internal static class UpdateCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
    internal static readonly Option<FileInfo> SolutionOrProjectFileOption = new("--solution-or-project") { IsRequired = true };
    internal static readonly Option<string> DependencyNameOption = new("--dependency") { IsRequired = true };
    internal static readonly Option<string> NewVersionOption = new("--new-version") { IsRequired = true };
    internal static readonly Option<string> PreviousVersionOption = new("--previous-version") { IsRequired = true };
    internal static readonly Option<bool> IsTransitiveOption = new("--transitive", getDefaultValue: () => false);
    internal static readonly Option<string?> ResultOutputPathOption = new("--result-output-path", getDefaultValue: () => null);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("update", "Applies the changes from an analysis report to update a dependency.")
        {
            JobPathOption,
            RepoRootOption,
            SolutionOrProjectFileOption,
            DependencyNameOption,
            NewVersionOption,
            PreviousVersionOption,
            IsTransitiveOption,
            ResultOutputPathOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (jobPath, repoRoot, solutionOrProjectFile, dependencyName, newVersion, previousVersion, isTransitive, resultOutputPath) =>
        {
            var logger = new ConsoleLogger();
            var experimentsManager = await ExperimentsManager.FromJobFileAsync(jobPath.FullName, logger);
            var worker = new UpdaterWorker(experimentsManager, logger);
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName, dependencyName, previousVersion, newVersion, isTransitive, resultOutputPath);
            setExitCode(0);
        }, JobPathOption, RepoRootOption, SolutionOrProjectFileOption, DependencyNameOption, NewVersionOption, PreviousVersionOption, IsTransitiveOption, ResultOutputPathOption);

        return command;
    }
}
