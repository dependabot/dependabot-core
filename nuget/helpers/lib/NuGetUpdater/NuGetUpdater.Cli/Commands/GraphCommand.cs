using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Graph;
using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Cli.Commands;

internal static class GraphCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { Required = true };
    internal static readonly Option<DirectoryInfo> RepoContentsPathOption = new("--repo-contents-path") { Required = true };
    internal static readonly Option<Uri> ApiUrlOption = new("--api-url")
    {
        Required = true,
        CustomParser = (argumentResult) => Uri.TryCreate(argumentResult.Tokens.Single().Value, UriKind.Absolute, out var uri) ? uri : throw new ArgumentException("Invalid API URL format.")
    };
    internal static readonly Option<string> JobIdOption = new("--job-id") { Required = true };
    internal static readonly Option<string> BaseCommitShaOption = new("--base-commit-sha") { Required = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("graph", "Runs dependency graph generation and submission.")
        {
            JobPathOption,
            RepoContentsPathOption,
            ApiUrlOption,
            JobIdOption,
            BaseCommitShaOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var jobPath = parseResult.GetValue(JobPathOption);
            var repoContentsPath = parseResult.GetValue(RepoContentsPathOption);
            var apiUrl = parseResult.GetValue(ApiUrlOption);
            var jobId = parseResult.GetValue(JobIdOption);
            var baseCommitSha = parseResult.GetValue(BaseCommitShaOption);

            var apiHandler = new HttpApiHandler(apiUrl!.ToString(), jobId!);
            var (experimentsManager, _errorResult) = await ExperimentsManager.FromJobFileAsync(jobId!, jobPath!.FullName);
            var logger = new OpenTelemetryLogger();
            var discoverWorker = new DiscoveryWorker(jobId!, experimentsManager, logger);
            var worker = new GraphWorker(jobId!, apiHandler, discoverWorker, logger);
            var result = await worker.RunAsync(jobPath!, repoContentsPath!, baseCommitSha!);
            setExitCode(result);
            return 0;
        });

        return command;
    }
}
