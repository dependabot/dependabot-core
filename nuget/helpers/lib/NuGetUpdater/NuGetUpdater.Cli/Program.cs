using System;
using System.CommandLine;
using System.Linq;
using System.Threading.Tasks;

using NuGetUpdater.Cli.Commands;

namespace NuGetUpdater.Cli;

internal sealed class Program
{
    internal static async Task<int> Main(string[] args)
    {
        var exitCode = 0;
        Action<int> setExitCode = (int code) => exitCode = code;

        var command = new RootCommand()
        {
            FrameworkCheckCommand.GetCommand(setExitCode),
            UpdateCommand.GetCommand(setExitCode),
        };
        command.TreatUnmatchedTokensAsErrors = true;

        // trim quotes
        args = args.Select(x => x.Trim('"')).ToArray();

        var result = await command.InvokeAsync(args);
        if (result != 0)
        {
            exitCode = result;
        }

        return exitCode;
    }
}
