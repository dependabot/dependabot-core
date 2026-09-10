using System.Net;
using System.Text.RegularExpressions;

namespace NuGetUpdater.Core.Clone;

public class ShellGitCommandHandler : IGitCommandHandler
{
    // Kept in sync with `GIT_SUBMODULE_CLONE_ERROR` in `common/lib/dependabot/file_fetchers/base.rb`.
    private static readonly Regex SubmoduleCloneFailure =
        new(@"^fatal: clone of '(?<url>.*)' into submodule path '.*' failed\r?$", RegexOptions.Multiline);

    private readonly ILogger _logger;

    public ShellGitCommandHandler(ILogger logger)
    {
        _logger = logger;
    }

    public async Task RunGitCommandAsync(IReadOnlyCollection<string> args, string? workingDirectory = null)
    {
        _logger.Info($"Running command: git {string.Join(" ", args)}{(workingDirectory is null ? "" : $" in directory {workingDirectory}")}");
        var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("git", args, workingDirectory);
        HandleErrorsFromOutput(stdout, stderr, _logger);
    }

    internal static void HandleErrorsFromOutput(string stdout, string stderr, ILogger? logger = null)
    {
        // Submodules might be in the repo but unrelated to dependencies, and submodule paths are
        // excluded from discovery, so a failed submodule clone need not fail the job.  git descends
        // into submodules only after the containing repository is cloned, so this line also tells us
        // the top-level clone succeeded.  stdout and stderr are matched together because git reports
        // the authentication failure and the submodule path on separate lines.
        var submoduleFailure = SubmoduleCloneFailure.Match($"{stdout}\n{stderr}");
        if (submoduleFailure.Success)
        {
            logger?.Error($"Cloning of submodule failed: {submoduleFailure.Groups["url"].Value}");
            return;
        }

        foreach (var output in new[] { stdout, stderr })
        {
            ThrowOnUnauthenticated(output);
        }
    }

    private static void ThrowOnUnauthenticated(string output)
    {
        if (output.Contains("Authentication failed for") ||
            output.Contains("could not read Username for"))
        {
            throw new HttpRequestException(output, inner: null, statusCode: HttpStatusCode.Unauthorized);
        }
    }
}
