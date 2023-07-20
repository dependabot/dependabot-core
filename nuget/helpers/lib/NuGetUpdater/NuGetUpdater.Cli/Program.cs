using System;
using System.CommandLine;
using System.IO;
using System.Threading.Tasks;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli;

public class Program
{
    public static async Task<int> Main(string[] args)
    {
        var repoRootOption = new Option<DirectoryInfo>("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
        var solutionOrProjectFileOption = new Option<FileInfo>("--solution-or-project") { IsRequired = true };
        var dependencyNameOption = new Option<string>("--dependency") { IsRequired = true };
        var newVersionOption = new Option<string>("--new-version") { IsRequired = true };
        var previousVersionOption = new Option<string>("--previous-version") { IsRequired = true };
        var isTransitiveOption = new Option<bool>("--transitive", getDefaultValue: () => false);
        var verboseOption = new Option<bool>("--verbose", getDefaultValue: () => false);

        var command = new RootCommand()
        {
            repoRootOption,
            solutionOrProjectFileOption,
            dependencyNameOption,
            newVersionOption,
            previousVersionOption,
            isTransitiveOption,
            verboseOption
        };
        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, solutionOrProjectFile, dependencyName, newVersion, previousVersion, isTransitive, verbose) =>
        {
            var worker = new NuGetUpdaterWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName, dependencyName, previousVersion, newVersion, isTransitive);
        }, repoRootOption, solutionOrProjectFileOption, dependencyNameOption, newVersionOption, previousVersionOption, isTransitiveOption, verboseOption);

        var result = await command.InvokeAsync(args);
        return result;
    }
}