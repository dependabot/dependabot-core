using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.DependencySolver;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Updater.FileWriters;

namespace NuGetUpdater.Cli.Commands;

internal static class RunCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { Required = true };
    internal static readonly Option<DirectoryInfo> RepoContentsPathOption = new("--repo-contents-path") { Required = true };
    internal static readonly Option<DirectoryInfo?> CaseInsensitiveRepoContentsPathOption = new("--case-insensitive-repo-contents-path") { Required = false };
    internal static readonly Option<Uri> ApiUrlOption = new("--api-url")
    {
        Required = true,
        CustomParser = (argumentResult) => Uri.TryCreate(argumentResult.Tokens.Single().Value, UriKind.Absolute, out var uri) ? uri : throw new ArgumentException("Invalid API URL format.")
    };
    internal static readonly Option<Uri> ExternalFileUpdaterUrl = new("--external-file-updater-url")
    {
        Required = false,
        CustomParser = (argumentResult) => Uri.TryCreate(argumentResult.Tokens.Single().Value, UriKind.Absolute, out var uri) ? uri : throw new ArgumentException("Invalid external file updater URL format.")
    };
    internal static readonly Option<string> JobIdOption = new("--job-id") { Required = true };
    internal static readonly Option<FileInfo> OutputPathOption = new("--output-path") { Required = true };
    internal static readonly Option<string> BaseCommitShaOption = new("--base-commit-sha") { Required = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("run", "Runs a full dependabot job.")
        {
            JobPathOption,
            RepoContentsPathOption,
            CaseInsensitiveRepoContentsPathOption,
            ApiUrlOption,
            ExternalFileUpdaterUrl,
            JobIdOption,
            OutputPathOption,
            BaseCommitShaOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var jobPath = parseResult.GetValue(JobPathOption);
            var repoContentsPath = parseResult.GetValue(RepoContentsPathOption);
            var caseInsensitiveRepoContentsPath = parseResult.GetValue(CaseInsensitiveRepoContentsPathOption);
            var apiUrl = parseResult.GetValue(ApiUrlOption);
            var externalFileUpdaterUrl = parseResult.GetValue(ExternalFileUpdaterUrl);
            var jobId = parseResult.GetValue(JobIdOption);
            var outputPath = parseResult.GetValue(OutputPathOption);
            var baseCommitSha = parseResult.GetValue(BaseCommitShaOption);

            var apiHandler = new HttpApiHandler(apiUrl!.ToString(), jobId!);
            var (experimentsManager, _errorResult) = await ExperimentsManager.FromJobFileAsync(jobId!, jobPath!.FullName);
            var logger = new OpenTelemetryLogger();
            var discoveryWorker = new DiscoveryWorker(jobId!, experimentsManager, logger);
            var analyzeWorker = new AnalyzeWorker(jobId!, experimentsManager, logger);
            var dependencySolverFactory = new DependencySolverFactory(workspacePath => new MSBuildDependencySolver(repoContentsPath!, new FileInfo(workspacePath), logger));
            var fileWriters = new List<IFileWriter>()
            {
                new XmlFileWriter(logger)
            };
            if (externalFileUpdaterUrl is not null)
            {
                fileWriters.Add(new ExternalFileWriter(externalFileUpdaterUrl.ToString(), logger));
            }

            var updateWorker = new UpdaterWorker(
                jobId!,
                discoveryWorker,
                dependencySolverFactory,
                fileWriters,
                PackageReferenceUpdater.ComputeUpdateOperations,
                experimentsManager,
                logger);
            var worker = new RunWorker(jobId!, apiHandler, discoveryWorker, analyzeWorker, updateWorker, logger);
            await worker.RunAsync(jobPath!, repoContentsPath!, caseInsensitiveRepoContentsPath, baseCommitSha!, outputPath!);
            return 0;
        });

        return command;
    }
}
