using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Clone;
using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Cli.Commands;

internal static class CloneCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { Required = true };
    internal static readonly Option<DirectoryInfo> RepoContentsPathOption = new("--repo-contents-path") { Required = true };
    internal static readonly Option<Uri> ApiUrlOption = new("--api-url")
    {
        Required = true,
        CustomParser = (argumentResult) => Uri.TryCreate(argumentResult.Tokens.Single().Value, UriKind.Absolute, out var uri) ? uri : throw new ArgumentException("Invalid API URL format.")
    };
    internal static readonly Option<string> JobIdOption = new("--job-id") { Required = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        var command = new Command("clone", "Clones a repository in preparation for a dependabot job.")
        {
            JobPathOption,
            RepoContentsPathOption,
            ApiUrlOption,
            JobIdOption,
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetAction(async (parseResult, cancellationToken) =>
        {
            var jobPath = parseResult.GetValue(JobPathOption);
            var repoContentsPath = parseResult.GetValue(RepoContentsPathOption);
            var apiUrl = parseResult.GetValue(ApiUrlOption);
            var jobId = parseResult.GetValue(JobIdOption);

            var apiHandler = new HttpApiHandler(apiUrl!.ToString(), jobId!);
            var logger = new OpenTelemetryLogger();
            var gitCommandHandler = new ShellGitCommandHandler(logger);
            var worker = new CloneWorker(jobId!, apiHandler, gitCommandHandler, logger);
            var exitCode = await worker.RunAsync(jobPath!, repoContentsPath!);
            setExitCode(exitCode);
            return exitCode;
        });

        return command;
    }
}
