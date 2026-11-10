using System.Net;

namespace NuGetUpdater.Core.Clone;

public class ShellGitCommandHandler : IGitCommandHandler
{
    private readonly ILogger _logger;

    public ShellGitCommandHandler(ILogger logger)
    {
        _logger = logger;
    }

    public async Task RunGitCommandAsync(IReadOnlyCollection<string> args, string? workingDirectory = null)
    {
        _logger.Info($"Running command: git {string.Join(" ", args)}{(workingDirectory is null ? "" : $" in directory {workingDirectory}")}");
        (int exitCode, string? stdout, string? stderr) = await ProcessEx.RunAsync("git", args, workingDirectory);
        HandleErrorsFromOutput(exitCode, stdout, stderr, _logger);
    }

    internal static void HandleErrorsFromOutput(int exitCode, string stdout, string stderr, ILogger logger)
    {
        foreach (string? output in new[] { stdout, stderr })
        {
            ThrowOnUnauthenticated(output);
        }

        if (exitCode != 0)
        {
            if (!string.IsNullOrWhiteSpace(stdout))
            {
                logger.Info($"Git command output: {stdout}");
            }

            if (!string.IsNullOrWhiteSpace(stderr))
            {
                logger.Error($"Git command error output: {stderr}");
            }

            throw new InvalidOperationException($"Git command failed with exit code {exitCode}.");
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
