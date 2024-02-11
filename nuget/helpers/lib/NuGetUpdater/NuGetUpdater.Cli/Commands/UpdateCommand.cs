using System;
using System.Collections.Generic;
using System.CommandLine;
using System.CommandLine.Parsing;
using System.IO;
using System.Text.Json;

using NuGetUpdater.Core;

namespace NuGetUpdater.Cli.Commands;

internal static class UpdateCommand
{
    internal static readonly Option<DirectoryInfo> RepoRootOption = new("--repo-root", () => new DirectoryInfo(Environment.CurrentDirectory)) { IsRequired = false };
    internal static readonly Option<FileInfo> SolutionOrProjectFileOption = new("--solution-or-project") { IsRequired = true };
    internal static readonly Option<IReadOnlyCollection<DependencyRequest>> DependencyOption = new("--dependency", ParseDependencyArgument) { IsRequired = true, Arity = ArgumentArity.OneOrMore };
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

        command.SetHandler(async (repoRoot, solutionOrProjectFile, dependencies, verbose) =>
        {
            var worker = new UpdaterWorker(new Logger(verbose));
            await worker.RunAsync(repoRoot.FullName, solutionOrProjectFile.FullName, dependencies);
            setExitCode(0);
        }, RepoRootOption, SolutionOrProjectFileOption, DependencyOption, VerboseOption);

        return command;
    }

    private static IReadOnlyCollection<DependencyRequest> ParseDependencyArgument(ArgumentResult result)
    {
        var dependencyRequests = new List<DependencyRequest>(result.Tokens.Count);
        foreach (var token in result.Tokens)
        {
            DependencyRequest? dependencyRequest;
            try
            {
                dependencyRequest = JsonSerializer.Deserialize(token.Value, NugetUpdaterJsonSerializerContext.Default.DependencyRequest);
            }
            catch (JsonException e)
            {
                result.ErrorMessage = $"Unable to deserialize '{token.Value.ReplaceLineEndings(string.Empty)}': {e.Message}";
                continue;
            }

            if (dependencyRequest is null)
            {
                result.ErrorMessage = $"Unable to deserialize {token.Value.ReplaceLineEndings(string.Empty)}";
                continue;
            }

            dependencyRequests.Add(dependencyRequest);
        }

        return dependencyRequests;
    }
}
