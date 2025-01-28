using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Clone;
using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Cli.Commands;

internal static class CloneCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> RepoContentsPathOption = new("--repo-contents-path") { IsRequired = true };
    internal static readonly Option<Uri> ApiUrlOption = new("--api-url") { IsRequired = true };
    internal static readonly Option<string> JobIdOption = new("--job-id") { IsRequired = true };

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

        command.SetHandler(async (jobPath, repoContentsPath, apiUrl, jobId) =>
        {
            var apiHandler = new HttpApiHandler(apiUrl.ToString(), jobId);
            var logger = new ConsoleLogger();
            var gitCommandHandler = new ShellGitCommandHandler(logger);
            var worker = new CloneWorker(jobId, apiHandler, gitCommandHandler);
            var exitCode = await worker.RunAsync(jobPath, repoContentsPath);
            setExitCode(exitCode);
        }, JobPathOption, RepoContentsPathOption, ApiUrlOption, JobIdOption);

        return command;
    }
}
