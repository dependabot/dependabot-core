using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Run;

namespace NuGetUpdater.Cli.Commands;

internal static class RunCommand
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { IsRequired = true };
    internal static readonly Option<DirectoryInfo> RepoContentsPathOption = new("--repo-contents-path") { IsRequired = true };
    internal static readonly Option<Uri> ApiUrlOption = new("--api-url") { IsRequired = true };
    internal static readonly Option<string> JobIdOption = new("--job-id") { IsRequired = true };
    internal static readonly Option<FileInfo> OutputPathOption = new("--output-path") { IsRequired = true };
    internal static readonly Option<string> BaseCommitShaOption = new("--base-commit-sha") { IsRequired = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("run", "Runs a full dependabot job.")
        {
            JobPathOption,
            RepoContentsPathOption,
            ApiUrlOption,
            JobIdOption,
            OutputPathOption,
            BaseCommitShaOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (jobPath, repoContentsPath, apiUrl, jobId, outputPath, baseCommitSha) =>
        {
            var apiHandler = new HttpApiHandler(apiUrl.ToString(), jobId);
            var worker = new RunWorker(apiHandler, new ConsoleLogger());
            await worker.RunAsync(jobPath, repoContentsPath, baseCommitSha, outputPath);
        }, JobPathOption, RepoContentsPathOption, ApiUrlOption, JobIdOption, OutputPathOption, BaseCommitShaOption);

        return command;
    }
}
