using System.CommandLine;
using System.Threading.Tasks;

using NuGetUpdater.Cli.Commands;

namespace NuGetUpdater.Cli;

internal sealed class Program
{
    internal static async Task<int> Main(string[] args)
    {
        var command = new RootCommand()
        {
            UpdateCommand.GetCommand(),
        };
        command.TreatUnmatchedTokensAsErrors = true;

        return await command.InvokeAsync(args);
    }
}