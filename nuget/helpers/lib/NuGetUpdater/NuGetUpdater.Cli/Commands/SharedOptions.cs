using System.CommandLine;

namespace NuGetUpdater.Cli.Commands;

internal static class SharedOptions
{
    internal static readonly Option<FileInfo> JobPathOption = new("--job-path") { Required = true };
    internal static readonly Option<DirectoryInfo> RepoContentsPathOption = new("--repo-contents-path") { Required = true };
    internal static readonly Option<DirectoryInfo?> CaseInsensitiveRepoContentsPathOption = new("--case-insensitive-repo-contents-path") { Required = false };
    internal static readonly Option<Uri> ApiUrlOption = new("--api-url")
    {
        Required = true,
        CustomParser = (argumentResult) => Uri.TryCreate(argumentResult.Tokens.Single().Value, UriKind.Absolute, out var uri) ? uri : throw new ArgumentException("Invalid API URL format.")
    };
    internal static readonly Option<string> JobIdOption = new("--job-id") { Required = true };
    internal static readonly Option<string> BaseCommitShaOption = new("--base-commit-sha") { Required = true };
}
