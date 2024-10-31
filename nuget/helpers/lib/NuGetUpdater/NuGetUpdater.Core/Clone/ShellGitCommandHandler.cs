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
        _logger.Log($"Running command: git {string.Join(" ", args)}{(workingDirectory is null ? "" : $" in directory {workingDirectory}")}");
        var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("git", args, workingDirectory);
        HandleErrorsFromOutput(stdout, stderr);
    }

    internal static void HandleErrorsFromOutput(string stdout, string stderr)
    {
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
