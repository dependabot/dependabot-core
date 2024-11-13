namespace NuGetUpdater.Core.Clone;

public interface IGitCommandHandler
{
    Task RunGitCommandAsync(IReadOnlyCollection<string> args, string? workingDirectory = null);
}
