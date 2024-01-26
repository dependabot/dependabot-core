using System;
using System.Collections.Generic;
using System.CommandLine;
using System.IO;
using System.Linq;
using System.Text.Json;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli.Commands;

internal static class UpdateCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
    internal static readonly Option<FileInfo> SolutionOrProjectFileOption = new("--solution-or-project") { IsRequired = true };
    internal static readonly Option<IEnumerable<string>> DependencyOption = new("--dependency") { IsRequired = true, Arity = ArgumentArity.OneOrMore };
    internal static readonly Option<bool> VerboseOption = new("--verbose", getDefaultValue: () => false);

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("update", "Applies the changes from an analysis report to update a dependency.")
        {
            RepoRootOption,
            SolutionOrProjectFileOption,
            DependencyOption,
            VerboseOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetHandler(async (repoRoot, solutionOrProjectFile, jsonDependencies, verbose) =>
        {
            var dependencies = DeserializeDependencies(jsonDependencies).ToList();

            var worker = new UpdaterWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName, dependencies);
            setExitCode(0);
        }, RepoRootOption, SolutionOrProjectFileOption, DependencyOption, VerboseOption);

        return command;
    }

    private static IEnumerable<DependencyRequest> DeserializeDependencies(IEnumerable<string> dependencies)
    {
        foreach (string dependency in dependencies)
        {
            yield return JsonSerializer.Deserialize(dependency, NugetUpdaterJsonSerializerContext.Default.DependencyRequest) ?? throw new Exception($"Unable to deserialize {dependency}");
        }
    }
}
