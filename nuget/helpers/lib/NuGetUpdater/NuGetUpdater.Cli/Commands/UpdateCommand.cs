using System.CommandLine;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli.Commands;

internal static class UpdateCommand
{
    internal static readonly Option<string> JobIdOption = new("--job-id") { Required = true };
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { Required = true };
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root") { DefaultValueFactory = _ => new DirectoryInfo(Environment.CurrentDirectory), Required = false };
    internal static readonly Option<FileInfo> SolutionOrProjectFileOption = new("--solution-or-project") { Required = true };
    internal static readonly Option<string> DependencyNameOption = new("--dependency") { Required = true };
    internal static readonly Option<string> NewVersionOption = new("--new-version") { Required = true };
    internal static readonly Option<string> PreviousVersionOption = new("--previous-version") { Required = true };
    internal static readonly Option<bool> IsTransitiveOption = new("--transitive") { DefaultValueFactory = _ => false };
    internal static readonly Option<string?> ResultOutputPathOption = new("--result-output-path") { DefaultValueFactory = _ => null };

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
        command.SetAction(async (parseResult, cancellationToken) =>
        {
            // since we have more than 8 arguments, we have to pull them out manually
            var jobId = parseResult.GetValue(JobIdOption)!;
            var jobPath = parseResult.GetValue(JobPathOption)!;
            var repoRoot = parseResult.GetValue(RepoRootOption)!;
            var solutionOrProjectFile = parseResult.GetValue(SolutionOrProjectFileOption)!;
            var dependencyName = parseResult.GetValue(DependencyNameOption)!;
            var newVersion = parseResult.GetValue(NewVersionOption)!;
            var previousVersion = parseResult.GetValue(PreviousVersionOption)!;
            var isTransitive = parseResult.GetValue(IsTransitiveOption);
            var resultOutputPath = parseResult.GetValue(ResultOutputPathOption);

            var (experimentsManager, _error) = await ExperimentsManager.FromJobFileAsync(jobId, jobPath.FullName);
            var logger = new OpenTelemetryLogger();
            var worker = new UpdaterWorker(jobId, experimentsManager, logger);
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName, dependencyName, previousVersion, newVersion, isTransitive, resultOutputPath);
            setExitCode(0);
            return 0;
        });

        return command;
    }
}
