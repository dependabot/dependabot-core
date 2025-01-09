using System.CommandLine;

using NuGetUpdater.Cli.Commands;

namespace NuGetUpdater.Cli;

internal sealed class Program
{
    internal static async Task<int> Main(string[] args)
    {
        var exitCode = 0;
        Action<int> setExitCode = code => exitCode = code;

        var command = new RootCommand
        {
            CloneCommand.GetCommand(setExitCode),
            FrameworkCheckCommand.GetCommand(setExitCode),
            DiscoverCommand.GetCommand(setExitCode),
            AnalyzeCommand.GetCommand(setExitCode),
            UpdateCommand.GetCommand(setExitCode),
            RunCommand.GetCommand(setExitCode),
        };
        command.TreatUnmatchedTokensAsErrors = true;

        var result = await command.InvokeAsync(args);

        return result == 0
            ? exitCode
            : result;
    }
}
