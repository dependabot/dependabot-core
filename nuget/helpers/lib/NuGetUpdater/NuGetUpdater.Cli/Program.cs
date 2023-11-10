using System.CommandLine;
using System.IO;
using System.Threading.Tasks;
using NuGetUpdater.Core;

namespace NuGetUpdater.Cli;

public class Program
{
    public static async Task<int> Main(string[] args)
    {
        var solutionOrProjectFileOption = new Option<FileInfo>("--solution-or-project") { IsRequired = true };
        var dependencyNameOption = new Option<string>("--dependency") { IsRequired = true };
        var newVersionOption = new Option<string>("--new-version") { IsRequired = true };
        var previousVersionOption = new Option<string>("--previous-version") { IsRequired = true };
        var verboseOption = new Option<bool>("--verbose", getDefaultValue: () => false);

        var command = new RootCommand()
        {
            solutionOrProjectFileOption,
            dependencyNameOption,
            newVersionOption,
            previousVersionOption,
            verboseOption
        };
        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (solutionOrProjectFile, dependencyName, newVersion, previousVersion, verbose) =>
        {
            var worker = new NuGetUpdaterWorker(verbose);
            await worker.RunAsync(solutionOrProjectFile.FullName, dependencyName, previousVersion, newVersion);
        }, solutionOrProjectFileOption, dependencyNameOption, newVersionOption, previousVersionOption, verboseOption);

        var result = await command.InvokeAsync(args);
        return result;
    }
}
