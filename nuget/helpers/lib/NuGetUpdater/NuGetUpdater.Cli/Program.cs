using System.CommandLine;
using System.Text;

using NuGetUpdater.Cli.Commands;

namespace NuGetUpdater.Cli;

internal sealed class Program
{
    internal static async Task<int> Main(string[] args)
    {
        // Allow loading of legacy code pages.  This is useful for being able to load XML files with
        //   <?xml version="1.0" encoding="windows-1252"?>
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

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
