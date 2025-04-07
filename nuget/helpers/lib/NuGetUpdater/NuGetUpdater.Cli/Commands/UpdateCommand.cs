using System.CommandLine;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli.Commands;

internal static class UpdateCommand
{
    internal static readonly Option<string> JobIdOption = new("--job-id") { IsRequired = true };
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
            JobIdOption,
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
        command.SetHandler(async (context) =>
        {
            // since we have more than 8 arguments, we have to pull them out manually
            var jobId = context.ParseResult.GetValueForOption(JobIdOption)!;
            var jobPath = context.ParseResult.GetValueForOption(JobPathOption)!;
            var repoRoot = context.ParseResult.GetValueForOption(RepoRootOption)!;
            var solutionOrProjectFile = context.ParseResult.GetValueForOption(SolutionOrProjectFileOption)!;
            var dependencyName = context.ParseResult.GetValueForOption(DependencyNameOption)!;
            var newVersion = context.ParseResult.GetValueForOption(NewVersionOption)!;
            var previousVersion = context.ParseResult.GetValueForOption(PreviousVersionOption)!;
            var isTransitive = context.ParseResult.GetValueForOption(IsTransitiveOption);
            var resultOutputPath = context.ParseResult.GetValueForOption(ResultOutputPathOption);

            var (experimentsManager, _error) = await ExperimentsManager.FromJobFileAsync(jobId, jobPath.FullName);
            var logger = new OpenTelemetryLogger();
            var worker = new UpdaterWorker(jobId, experimentsManager, logger);
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName, dependencyName, previousVersion, newVersion, isTransitive, resultOutputPath);
            setExitCode(0);
        });

        return command;
    }
}
