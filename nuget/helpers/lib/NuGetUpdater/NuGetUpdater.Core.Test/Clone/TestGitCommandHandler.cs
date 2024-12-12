using NuGetUpdater.Core.Clone;

namespace NuGetUpdater.Core.Test.Clone;

internal class TestGitCommandHandler : IGitCommandHandler
{
    private readonly List<(string[] Args, string? WorkingDirectory)> _seenCommands = new();

    public IReadOnlyCollection<(string[] Args, string? WorkingDirectory)> SeenCommands => _seenCommands;

    public virtual Task RunGitCommandAsync(IReadOnlyCollection<string> args, string? workingDirectory = null)
    {
        _seenCommands.Add((args.ToArray(), workingDirectory));
        return Task.CompletedTask;
    }
}
