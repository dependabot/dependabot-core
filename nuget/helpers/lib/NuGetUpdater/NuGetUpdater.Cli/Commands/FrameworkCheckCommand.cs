using System.CommandLine;

using NuGetUpdater.Core;
using NuGetUpdater.Core.FrameworkChecker;

namespace NuGetUpdater.Cli.Commands;

internal static class FrameworkCheckCommand
{
    internal static readonly Option<string[]> ProjectTfmsOption = new("--project-tfms") { Required = true, AllowMultipleArgumentsPerToken = true };
    internal static readonly Option<string[]> PackageTfmsOption = new("--package-tfms") { Required = true, AllowMultipleArgumentsPerToken = true };

    internal static Command GetCommand(Action<int> setExitCode)
    {
        Command command = new("framework-check", "Checks that a project's target frameworks are satisfied by the target frameworks supported by a package.")
        {
            ProjectTfmsOption,
            PackageTfmsOption
        };

        command.TreatUnmatchedTokensAsErrors = true;

        command.SetAction((parseResult) =>
        {
            var projectTfms = parseResult.GetValue(ProjectTfmsOption);
            var packageTfms = parseResult.GetValue(PackageTfmsOption);

            setExitCode(CompatibilityChecker.IsCompatible(projectTfms!, packageTfms!, new ConsoleLogger())
                ? 0
                : 1);
        });

        return command;
    }
}
